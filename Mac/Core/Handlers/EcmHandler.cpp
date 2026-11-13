// EcmHandler.cpp -- ECM (Error Code Modeler, Neill Corlett's ECM tool; a macOS addition, after
// Iso7z). ECM stores a CD image (usually a raw .bin) without what can be recomputed: the sync
// and the EDC / ECC of every Mode 1 / Mode 2 sector, and the address of Mode 2 sectors. The
// handler indexes the records once and rebuilds each sector on demand, so the image (named after
// the .ecm without its extension) reads like the original file.

#include "StdAfx.h"

#include "../../../C/CpuArch.h"

#include "../../../CPP/Common/ComTry.h"
#include "../../../CPP/Common/MyBuffer.h"
#include "../../../CPP/Windows/PropVariant.h"
#include "../../../CPP/7zip/Archive/HandlerCont.h"
#include "../../../CPP/7zip/Common/RegisterArc.h"
#include "../../../CPP/7zip/Common/StreamUtils.h"

using namespace NWindows;

namespace NArchive {
namespace NEcm {

static const Byte kSignature[] = { 'E', 'C', 'M', 0 };

// ---------------------------------------------------------------------------------------------
// EDC (CRC-32, polynomial 0xD8018001 reflected) and ECC (the P and Q Reed-Solomon parities)

static UInt32 g_EdcTable[256];
static Byte g_EccF[256];
static Byte g_EccB[256];

static void InitTables()
{
  static bool done = false;
  if (done)
    return;
  for (UInt32 i = 0; i < 256; i++)
  {
    const UInt32 j = (i << 1) ^ ((i & 0x80) ? 0x11D : 0);
    g_EccF[i] = (Byte)j;
    g_EccB[i ^ j] = (Byte)i;
    UInt32 edc = i;
    for (unsigned k = 0; k < 8; k++)
      edc = (edc >> 1) ^ ((edc & 1) ? 0xD8018001 : 0);
    g_EdcTable[i] = edc;
  }
  done = true;
}

static UInt32 Edc(const Byte *p, size_t size)
{
  UInt32 edc = 0;
  for (size_t i = 0; i < size; i++)
    edc = (edc >> 8) ^ g_EdcTable[(edc ^ p[i]) & 0xFF];
  return edc;
}

static void EccBlock(const Byte *src, unsigned majorCount, unsigned minorCount,
    unsigned majorMult, unsigned minorInc, Byte *dest)
{
  const unsigned size = majorCount * minorCount;
  for (unsigned major = 0; major < majorCount; major++)
  {
    unsigned index = (major >> 1) * majorMult + (major & 1);
    Byte a = 0, b = 0;
    for (unsigned minor = 0; minor < minorCount; minor++)
    {
      const Byte t = src[index];
      index += minorInc;
      if (index >= size)
        index -= size;
      a ^= t;
      b ^= t;
      a = g_EccF[a];
    }
    a = g_EccB[g_EccF[a] ^ b];
    dest[major] = a;
    dest[major + majorCount] = (Byte)(a ^ b);
  }
}

// The P and Q parities over the header and data; Mode 2 computes them with a zero address.
static void Ecc(Byte *sector, bool zeroAddress)
{
  Byte address[4];
  if (zeroAddress)
  {
    memcpy(address, sector + 12, 4);
    memset(sector + 12, 0, 4);
  }
  EccBlock(sector + 0xC, 86, 24, 2, 86, sector + 0x81C);
  EccBlock(sector + 0xC, 52, 43, 86, 88, sector + 0x8C8);
  if (zeroAddress)
    memcpy(sector + 12, address, 4);
}

// Completes a sector whose stored parts are in place: type 1 Mode 1, 2 Mode 2 Form 1, 3 Form 2.
static void Rebuild(Byte *s, unsigned type)
{
  s[0] = 0;
  memset(s + 1, 0xFF, 10);
  s[11] = 0;
  switch (type)
  {
    case 1:
      s[15] = 1;
      SetUi32(s + 0x810, Edc(s, 0x810))
      memset(s + 0x814, 0, 8);
      Ecc(s, false);
      break;
    case 2:
      s[15] = 2;
      memcpy(s + 0x10, s + 0x14, 4);       // the subheader is stored once, written twice
      SetUi32(s + 0x818, Edc(s + 0x10, 0x808))
      Ecc(s, true);
      break;
    case 3:
      s[15] = 2;
      memcpy(s + 0x10, s + 0x14, 4);
      SetUi32(s + 0x92C, Edc(s + 0x10, 0x91C))
      break;
  }
}

// What a record of `type` stores per sector, and what it writes.
static const UInt32 kStored[4] = { 1, 3 + 2048, 4 + 2048, 4 + 2324 };
static const UInt32 kOutput[4] = { 1, 2352, 2336, 2336 };

// ---------------------------------------------------------------------------------------------

struct CRecord
{
  UInt64 OutPos;
  UInt64 InPos;
  UInt32 Count;     // bytes (type 0) or sectors
  Byte Type;
};

Z7_class_CHandler_final: public CHandlerImg
{
  CRecordVector<CRecord> _records;
  UInt64 _phySize;
  bool _isArc;
  bool _unexpectedEnd;
  Byte _sector[2352];
  UInt64 _sectorPos;      // output position of the sector in _sector, or ~0
  unsigned _sectorType;

  HRESULT Open2(IInStream *stream, IArchiveOpenCallback *openCallback) Z7_override;
  HRESULT LoadSector(const CRecord &r, UInt64 index);

public:
  Z7_IFACE_COM7_IMP(IInArchive_Img)
  Z7_IFACE_COM7_IMP(IInArchiveGetStream)
  Z7_IFACE_COM7_IMP(ISequentialInStream)
  CHandler(): _phySize(0), _isArc(false), _unexpectedEnd(false), _sectorPos((UInt64)(Int64)-1), _sectorType(0) {}
};

HRESULT CHandler::Open2(IInStream *stream, IArchiveOpenCallback *openCallback)
{
  InitTables();
  Byte head[4];
  RINOK(ReadStream_FALSE(stream, head, 4))
  if (memcmp(head, kSignature, 4) != 0)
    return S_FALSE;
  UInt64 fileSize = 0;
  RINOK(InStream_GetSize_SeekToEnd(stream, fileSize))
  _isArc = true;
  UInt64 inPos = 4, outPos = 0;
  Byte buf[5];
  for (;;)
  {
    if (openCallback && (_records.Size() & 0xFFFF) == 0)
    {
      const UInt64 files = 0;
      RINOK(openCallback->SetCompleted(&files, &inPos))
    }
    // A record header: type in bits 0-1, count - 1 in the rest, 7 more bits per extra byte.
    RINOK(InStream_SeekSet(stream, inPos))
    size_t n = 5;
    RINOK(ReadStream(stream, buf, &n))
    if (n == 0)
    {
      _unexpectedEnd = true;
      break;
    }
    unsigned c = buf[0];
    unsigned used = 1;
    const unsigned type = c & 3;
    UInt32 num = (c >> 2) & 0x1F;
    unsigned bits = 5;
    while (c & 0x80)
    {
      if (used >= n || bits > 31)
        return S_FALSE;
      c = buf[used++];
      num |= (UInt32)(c & 0x7F) << bits;
      bits += 7;
    }
    inPos += used;
    if (num == 0xFFFFFFFF)
      break;                                // the end; a 4-byte EDC of the whole image follows
    num++;
    if (num >= 0x80000000)
      return S_FALSE;
    CRecord r;
    r.OutPos = outPos;
    r.InPos = inPos;
    r.Count = num;
    r.Type = (Byte)type;
    const UInt64 stored = (UInt64)num * kStored[type];
    if (inPos + stored > fileSize)
    {
      _unexpectedEnd = true;
      break;
    }
    _records.Add(r);
    inPos += stored;
    outPos += (UInt64)num * kOutput[type];
  }
  _size = outPos;
  _phySize = inPos + 4 <= fileSize ? inPos + 4 : fileSize;
  Stream = stream;
  return S_OK;
}

HRESULT CHandler::LoadSector(const CRecord &r, UInt64 index)
{
  Byte *s = _sector;
  memset(s, 0, sizeof(_sector));
  const UInt64 at = r.InPos + index * kStored[r.Type];
  RINOK(InStream_SeekSet(Stream, at))
  switch (r.Type)
  {
    case 1: RINOK(ReadStream_FALSE(Stream, s + 12, 3)) RINOK(ReadStream_FALSE(Stream, s + 16, 2048)) break;
    case 2: RINOK(ReadStream_FALSE(Stream, s + 0x14, 4 + 2048)) break;
    case 3: RINOK(ReadStream_FALSE(Stream, s + 0x14, 4 + 2324)) break;
  }
  Rebuild(s, r.Type);
  _sectorPos = r.OutPos + index * kOutput[r.Type];
  _sectorType = r.Type;
  return S_OK;
}

Z7_COM7F_IMF(CHandler::Read(void *data, UInt32 size, UInt32 *processedSize))
{
  if (processedSize)
    *processedSize = 0;
  if (_virtPos >= _size || size == 0)
    return S_OK;
  if (size > _size - _virtPos)
    size = (UInt32)(_size - _virtPos);
  // the record holding _virtPos
  unsigned lo = 0, hi = _records.Size();
  while (hi - lo > 1)
  {
    const unsigned mid = (lo + hi) / 2;
    if (_records[mid].OutPos <= _virtPos)
      lo = mid;
    else
      hi = mid;
  }
  if (_records.IsEmpty())
    return S_OK;
  const CRecord &r = _records[lo];
  const UInt64 rel = _virtPos - r.OutPos;
  if (r.Type == 0)
  {
    const UInt64 rem = (UInt64)r.Count - rel;
    if (size > rem)
      size = (UInt32)rem;
    RINOK(InStream_SeekSet(Stream, r.InPos + rel))
    RINOK(ReadStream_FALSE(Stream, data, size))
  }
  else
  {
    const UInt32 out = kOutput[r.Type];
    const UInt64 index = rel / out;
    const UInt32 within = (UInt32)(rel - index * out);
    if (_sectorPos != r.OutPos + index * out)
    {
      const HRESULT res = LoadSector(r, index);
      if (res != S_OK)
      {
        _sectorPos = (UInt64)(Int64)-1;
        return res;
      }
    }
    // Mode 2 records write the sector from its subheader on (2336 bytes).
    const Byte *src = _sector + (r.Type == 1 ? 0 : 0x10);
    UInt32 rem = out - within;
    if (size > rem)
      size = rem;
    memcpy(data, src + within, size);
  }
  _virtPos += size;
  if (processedSize)
    *processedSize = size;
  return S_OK;
}

static const Byte kProps[] = { kpidSize, kpidPackSize };
static const Byte kArcProps[] = { kpidNumBlocks };

IMP_IInArchive_Props
IMP_IInArchive_ArcProps

Z7_COM7F_IMF(CHandler::GetArchiveProperty(PROPID propID, PROPVARIANT *value))
{
  COM_TRY_BEGIN
  NCOM::CPropVariant prop;
  switch (propID)
  {
    case kpidPhySize: if (_phySize != 0) prop = _phySize; break;
    case kpidNumBlocks: prop = (UInt32)_records.Size(); break;
    case kpidErrorFlags:
    {
      UInt32 v = 0;
      if (!_isArc) v |= kpv_ErrorFlags_IsNotArc;
      if (_unexpectedEnd) v |= kpv_ErrorFlags_UnexpectedEnd;
      if (v != 0)
        prop = v;
      break;
    }
  }
  prop.Detach(value);
  return S_OK;
  COM_TRY_END
}

Z7_COM7F_IMF(CHandler::GetProperty(UInt32 /* index */, PROPID propID, PROPVARIANT *value))
{
  COM_TRY_BEGIN
  NCOM::CPropVariant prop;
  switch (propID)
  {
    case kpidSize: prop = _size; break;
    case kpidPackSize: if (_phySize != 0) prop = _phySize; break;
  }
  prop.Detach(value);
  return S_OK;
  COM_TRY_END
}

Z7_COM7F_IMF(CHandler::Close())
{
  _records.Clear();
  _phySize = 0;
  _isArc = false;
  _unexpectedEnd = false;
  _sectorPos = (UInt64)(Int64)-1;
  Clear_HandlerImg_Vars();
  Stream.Release();
  return S_OK;
}

Z7_COM7F_IMF(CHandler::GetStream(UInt32 /* index */, ISequentialInStream **stream))
{
  COM_TRY_BEGIN
  *stream = NULL;
  CMyComPtr<ISequentialInStream> streamTemp = this;
  _virtPos = 0;
  *stream = streamTemp.Detach();
  return S_OK;
  COM_TRY_END
}

REGISTER_ARC_I(
  "ECM", "ecm", NULL, 0x9A,
  kSignature,
  0,
  0,
  NULL)

}}
