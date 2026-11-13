// CompressedImages.cpp -- disc images compressed block by block (a macOS addition, after
// Iso7z): CSO / ZSO (PSP compressed ISO, deflate / LZ4), CISO (Wii compact ISO, unused blocks
// left out), ISZ (UltraISO, zlib / bzip2) and zisofs files (mkzftree). Each shows the image it
// holds as one file, which 7-Zip opens as ISO 9660 / UDF in turn.

#include "StdAfx.h"

#include "../../../C/CpuArch.h"

#include "../../../CPP/Common/ComTry.h"
#include "../../../CPP/Common/MyBuffer.h"
#include "../../../CPP/Windows/PropVariant.h"
#include "../../../CPP/7zip/Archive/HandlerCont.h"
#include "../../../CPP/7zip/Common/RegisterArc.h"
#include "../../../CPP/7zip/Common/StreamObjects.h"
#include "../../../CPP/7zip/Common/StreamUtils.h"
#include "../../../CPP/7zip/Compress/BZip2Decoder.h"
#include "../../../CPP/7zip/Compress/DeflateDecoder.h"
#include "../../../CPP/7zip/Compress/ZlibDecoder.h"

#include "CompressedImages.h"

using namespace NWindows;

namespace NArchive {
namespace NBlockImage {

// ---------------------------------------------------------------------------------------------
// decoders

HRESULT Inflate(const Byte *in, size_t inSize, Byte *out, size_t outSize, bool zlib, size_t &produced)
{
  produced = 0;
  CMyComPtr2_Create<ISequentialInStream, CBufInStream> inStream;
  inStream->Init(in, inSize);
  CMyComPtr2_Create<ISequentialOutStream, CBufPtrSeqOutStream> outStream;
  outStream->Init(out, outSize);
  const UInt64 outSize64 = outSize;
  HRESULT res;
  if (zlib)
  {
    CMyComPtr2_Create<ICompressCoder, NCompress::NZlib::CDecoder> decoder;
    res = decoder.Interface()->Code(inStream, outStream, NULL, &outSize64, NULL);
  }
  else
  {
    CMyComPtr2_Create<ICompressCoder, NCompress::NDeflate::NDecoder::CCOMCoder> decoder;
    res = decoder.Interface()->Code(inStream, outStream, NULL, &outSize64, NULL);
  }
  produced = outStream->GetPos();
  return res;
}

HRESULT Bunzip2(const Byte *in, size_t inSize, Byte *out, size_t outSize, size_t &produced)
{
  produced = 0;
  CMyComPtr2_Create<ISequentialInStream, CBufInStream> inStream;
  inStream->Init(in, inSize);
  CMyComPtr2_Create<ISequentialOutStream, CBufPtrSeqOutStream> outStream;
  outStream->Init(out, outSize);
  const UInt64 outSize64 = outSize;
  CMyComPtr2_Create<ICompressCoder, NCompress::NBZip2::CDecoder> decoder;
  const HRESULT res = decoder.Interface()->Code(inStream, outStream, NULL, &outSize64, NULL);
  produced = outStream->GetPos();
  return res;
}

// An LZ4 block (no frame): literals and matches until the output is full or the input ends.
bool Lz4Block(const Byte *in, size_t inSize, Byte *out, size_t outSize, size_t &produced)
{
  size_t ip = 0, op = 0;
  produced = 0;
  while (ip < inSize)
  {
    const unsigned token = in[ip++];
    size_t lit = token >> 4;
    if (lit == 15)
    {
      unsigned b;
      do
      {
        if (ip >= inSize) return false;
        b = in[ip++];
        lit += b;
      }
      while (b == 255);
    }
    if (lit > inSize - ip || lit > outSize - op)
      return false;
    memcpy(out + op, in + ip, lit);
    ip += lit;
    op += lit;
    if (ip >= inSize || op >= outSize)
      break;                                  // the last sequence has literals only
    if (ip + 2 > inSize)
      return false;
    const size_t offset = GetUi16(in + ip);
    ip += 2;
    if (offset == 0 || offset > op)
      return false;
    size_t len = (token & 15);
    if (len == 15)
    {
      unsigned b;
      do
      {
        if (ip >= inSize) return false;
        b = in[ip++];
        len += b;
      }
      while (b == 255);
    }
    len += 4;
    if (len > outSize - op)
      len = outSize - op;
    for (size_t i = 0; i < len; i++, op++)    // byte by byte: a match may overlap its source
      out[op] = out[op - offset];
  }
  produced = op;
  return true;
}

// ---------------------------------------------------------------------------------------------
// a block-compressed image as one stream

Z7_COM7F_IMF(CBlockHandler::Read(void *data, UInt32 size, UInt32 *processedSize))
{
  if (processedSize)
    *processedSize = 0;
  if (_virtPos >= _size || size == 0)
    return S_OK;
  if (size > _size - _virtPos)
    size = (UInt32)(_size - _virtPos);
  const UInt64 block = _virtPos / _blockSize;
  const UInt32 within = (UInt32)(_virtPos - block * _blockSize);
  if (block != _cachedBlock)
  {
    _cachedBlock = (UInt64)(Int64)-1;
    if (_cache.Size() != _blockSize)
      _cache.Alloc(_blockSize);
    const HRESULT res = DecodeBlock(block, _cache);
    if (res != S_OK)
    {
      if (res == S_FALSE)
      {
        _stream_dataError = true;
        return S_FALSE;
      }
      return res;
    }
    _cachedBlock = block;
  }
  UInt32 rem = _blockSize - within;
  if (size > rem)
    size = rem;
  memcpy(data, _cache + within, size);
  _virtPos += size;
  if (processedSize)
    *processedSize = size;
  return S_OK;
}

HRESULT CBlockHandler::ReadAt(UInt64 offset, Byte *data, size_t size)
{
  RINOK(InStream_SeekSet(Stream, offset))
  return ReadStream_FALSE(Stream, data, size);
}

static const Byte kProps[] = { kpidSize, kpidPackSize };
static const Byte kArcProps[] = { kpidMethod, kpidClusterSize };

#define CHandler CBlockHandler
IMP_IInArchive_Props
IMP_IInArchive_ArcProps
#undef CHandler

Z7_COM7F_IMF(CBlockHandler::GetArchiveProperty(PROPID propID, PROPVARIANT *value))
{
  COM_TRY_BEGIN
  NCOM::CPropVariant prop;
  switch (propID)
  {
    case kpidMainSubfile: prop = (UInt32)0; break;
    case kpidPhySize: if (_phySize != 0) prop = _phySize; break;
    case kpidMethod: if (_method) prop = _method; break;
    case kpidClusterSize: prop = _blockSize; break;
    case kpidErrorFlags:
    {
      UInt32 v = 0;
      if (!_isArc) v |= kpv_ErrorFlags_IsNotArc;
      if (_unsupported) v |= kpv_ErrorFlags_UnsupportedMethod;
      if (v != 0)
        prop = v;
      break;
    }
  }
  prop.Detach(value);
  return S_OK;
  COM_TRY_END
}

Z7_COM7F_IMF(CBlockHandler::GetProperty(UInt32 /* index */, PROPID propID, PROPVARIANT *value))
{
  COM_TRY_BEGIN
  NCOM::CPropVariant prop;
  switch (propID)
  {
    case kpidSize: prop = _size; break;
    case kpidPackSize: if (_phySize != 0) prop = _phySize; break;
    case kpidExtension: if (_imgExt) prop = _imgExt; break;
  }
  prop.Detach(value);
  return S_OK;
  COM_TRY_END
}

Z7_COM7F_IMF(CBlockHandler::Close())
{
  _cache.Free();
  _cachedBlock = (UInt64)(Int64)-1;
  _phySize = 0;
  _isArc = false;
  _unsupported = false;
  CloseFormat();
  Clear_HandlerImg_Vars();
  Stream.Release();
  return S_OK;
}

Z7_COM7F_IMF(CBlockHandler::GetStream(UInt32 /* index */, ISequentialInStream **stream))
{
  COM_TRY_BEGIN
  *stream = NULL;
  if (_unsupported)
    return S_FALSE;
  CMyComPtr<ISequentialInStream> streamTemp = this;
  _virtPos = 0;
  *stream = streamTemp.Detach();
  return S_OK;
  COM_TRY_END
}

}

// =============================================================================================
// CSO (PSP, deflate; v2 also LZ4) and CISO (Wii): both start with "CISO".

namespace NCso {

using namespace NBlockImage;

static const Byte kSignature[] = { 'C', 'I', 'S', 'O' };

class CHandler: public CBlockHandler
{
  CRecordVector<UInt32> _index;     // CSO: numBlocks + 1 entries
  CRecordVector<UInt32> _wiiMap;    // Wii: the data position (in blocks) of each block, or ~0
  unsigned _align;
  unsigned _version;
  bool _wii;
  CByteBuffer _packed;

  HRESULT Open2(IInStream *stream, IArchiveOpenCallback *openCallback) Z7_override;
  HRESULT DecodeBlock(UInt64 block, Byte *out) Z7_override;
  void CloseFormat() Z7_override { _index.Clear(); _wiiMap.Clear(); _packed.Free(); }
};

HRESULT CHandler::Open2(IInStream *stream, IArchiveOpenCallback * /* openCallback */)
{
  Byte h[0x18];
  RINOK(ReadStream_FALSE(stream, h, sizeof(h)))
  if (memcmp(h, kSignature, 4) != 0)
    return S_FALSE;
  UInt64 fileSize = 0;
  RINOK(InStream_GetSize_SeekToEnd(stream, fileSize))
  Stream = stream;
  _phySize = fileSize;
  _imgExt = "iso";
  const UInt32 headerSize = GetUi32(h + 4);
  if (headerSize == 0x18 || headerSize == 0)
  {
    // PSP CSO: total size, block size, version, index alignment, then the index.
    _wii = false;
    _size = GetUi64(h + 8);
    _blockSize = GetUi32(h + 16);
    _version = h[20];
    _align = h[21];
    if (_blockSize < 0x200 || _blockSize > (1 << 24) || (_blockSize & (_blockSize - 1)) != 0 || _align > 31)
      return S_FALSE;
    const UInt64 numBlocks = (_size + _blockSize - 1) / _blockSize;
    if (numBlocks > (1 << 26) || 0x18 + (numBlocks + 1) * 4 > fileSize)
      return S_FALSE;
    _isArc = true;
    _method = _version >= 2 ? "CSO v2" : "CSO";
    CByteBuffer table((size_t)(numBlocks + 1) * 4);
    RINOK(InStream_SeekSet(stream, 0x18))
    RINOK(ReadStream_FALSE(stream, table, table.Size()))
    for (UInt64 i = 0; i <= numBlocks; i++)
      _index.Add(GetUi32(table + (size_t)i * 4));
    return S_OK;
  }
  // Wii CISO: "CISO", block size, then one byte per block (used or not) up to 0x8000; the used
  // blocks follow in order.
  _wii = true;
  _blockSize = headerSize;
  if (_blockSize < 0x8000 || _blockSize > (1 << 26) || (_blockSize & (_blockSize - 1)) != 0)
    return S_FALSE;
  Byte map[0x8000 - 8];
  RINOK(InStream_SeekSet(stream, 8))
  RINOK(ReadStream_FALSE(stream, map, sizeof(map)))
  UInt32 used = 0;
  unsigned last = 0;
  for (unsigned i = 0; i < sizeof(map); i++)
  {
    if (map[i] > 1)
      return S_FALSE;
    if (map[i])
    {
      _wiiMap.Add(used++);
      last = i + 1;
    }
    else
      _wiiMap.Add((UInt32)(Int32)-1);
  }
  if (used == 0)
    return S_FALSE;
  _isArc = true;
  _method = "CISO (Wii)";
  _imgExt = "iso";
  // A Wii disc is 4 699 979 776 or 8 511 160 320 bytes; unused tail blocks read as zeros.
  _size = (UInt64)last * _blockSize;
  if (_size < 4699979776ull && (UInt64)sizeof(map) * _blockSize >= 4699979776ull)
    _size = 4699979776ull;
  return S_OK;
}

HRESULT CHandler::DecodeBlock(UInt64 block, Byte *out)
{
  if (_wii)
  {
    if (block >= _wiiMap.Size() || _wiiMap[(unsigned)block] == (UInt32)(Int32)-1)
    {
      memset(out, 0, _blockSize);
      return S_OK;
    }
    return ReadAt(0x8000 + (UInt64)_wiiMap[(unsigned)block] * _blockSize, out, _blockSize);
  }
  if (block + 1 >= _index.Size())
    return S_FALSE;
  const UInt32 a = _index[(unsigned)block], b = _index[(unsigned)block + 1];
  const UInt64 start = (UInt64)(a & 0x7FFFFFFF) << _align;
  const UInt64 end = (UInt64)(b & 0x7FFFFFFF) << _align;
  if (end < start || end - start > (UInt64)_blockSize * 2 + 64)
    return S_FALSE;
  size_t packed = (size_t)(end - start);
  const bool plain = _version >= 2 ? packed >= _blockSize : (a & 0x80000000) != 0;
  const UInt64 want = (block + 1) * _blockSize <= _size ? _blockSize : _size - block * _blockSize;
  if (plain)
  {
    memset(out, 0, _blockSize);
    if (packed > _blockSize)
      packed = _blockSize;
    RINOK(InStream_SeekSet(Stream, start))
    size_t n = packed;
    RINOK(ReadStream(Stream, out, &n))
    return S_OK;
  }
  if (_packed.Size() < packed)
    _packed.Alloc(packed);
  RINOK(InStream_SeekSet(Stream, start))
  size_t n = packed;
  RINOK(ReadStream(Stream, _packed, &n))
  size_t produced = 0;
  if (_version >= 2 && (a & 0x80000000) != 0)
  {
    if (!Lz4Block(_packed, n, out, _blockSize, produced))
      return S_FALSE;
  }
  else
  {
    const HRESULT res = Inflate(_packed, n, out, _blockSize, false, produced);
    if (res != S_OK && produced < want)
      return S_FALSE;
  }
  if (produced < want)
    return S_FALSE;
  if (produced < _blockSize)
    memset(out + produced, 0, _blockSize - produced);
  return S_OK;
}

REGISTER_ARC_I(
  "CSO", "cso ciso", NULL, 0x96,
  kSignature,
  0,
  0,
  NULL)

}

// =============================================================================================
// ZSO (LZ4 compressed ISO): the CSO layout with "ZISO".

namespace NZso {

using namespace NBlockImage;

static const Byte kSignature[] = { 'Z', 'I', 'S', 'O' };

class CHandler: public CBlockHandler
{
  CRecordVector<UInt32> _index;
  unsigned _align;
  CByteBuffer _packed;

  HRESULT Open2(IInStream *stream, IArchiveOpenCallback *openCallback) Z7_override;
  HRESULT DecodeBlock(UInt64 block, Byte *out) Z7_override;
  void CloseFormat() Z7_override { _index.Clear(); _packed.Free(); }
};

HRESULT CHandler::Open2(IInStream *stream, IArchiveOpenCallback * /* openCallback */)
{
  Byte h[0x18];
  RINOK(ReadStream_FALSE(stream, h, sizeof(h)))
  if (memcmp(h, kSignature, 4) != 0)
    return S_FALSE;
  UInt64 fileSize = 0;
  RINOK(InStream_GetSize_SeekToEnd(stream, fileSize))
  _size = GetUi64(h + 8);
  _blockSize = GetUi32(h + 16);
  _align = h[21];
  if (_blockSize < 0x200 || _blockSize > (1 << 24) || (_blockSize & (_blockSize - 1)) != 0 || _align > 31)
    return S_FALSE;
  const UInt64 numBlocks = (_size + _blockSize - 1) / _blockSize;
  if (numBlocks > (1 << 26) || 0x18 + (numBlocks + 1) * 4 > fileSize)
    return S_FALSE;
  Stream = stream;
  _isArc = true;
  _phySize = fileSize;
  _imgExt = "iso";
  _method = "ZSO (LZ4)";
  CByteBuffer table((size_t)(numBlocks + 1) * 4);
  RINOK(InStream_SeekSet(stream, 0x18))
  RINOK(ReadStream_FALSE(stream, table, table.Size()))
  for (UInt64 i = 0; i <= numBlocks; i++)
    _index.Add(GetUi32(table + (size_t)i * 4));
  return S_OK;
}

HRESULT CHandler::DecodeBlock(UInt64 block, Byte *out)
{
  if (block + 1 >= _index.Size())
    return S_FALSE;
  const UInt32 a = _index[(unsigned)block], b = _index[(unsigned)block + 1];
  const UInt64 start = (UInt64)(a & 0x7FFFFFFF) << _align;
  const UInt64 end = (UInt64)(b & 0x7FFFFFFF) << _align;
  if (end < start || end - start > (UInt64)_blockSize * 2 + 64)
    return S_FALSE;
  size_t packed = (size_t)(end - start);
  if ((a & 0x80000000) != 0)
  {
    memset(out, 0, _blockSize);
    if (packed > _blockSize)
      packed = _blockSize;
    RINOK(InStream_SeekSet(Stream, start))
    size_t n = packed;
    return ReadStream(Stream, out, &n);
  }
  if (_packed.Size() < packed)
    _packed.Alloc(packed);
  RINOK(InStream_SeekSet(Stream, start))
  size_t n = packed;
  RINOK(ReadStream(Stream, _packed, &n))
  size_t produced = 0;
  if (!Lz4Block(_packed, n, out, _blockSize, produced))
    return S_FALSE;
  const UInt64 want = (block + 1) * _blockSize <= _size ? _blockSize : _size - block * _blockSize;
  if (produced < want)
    return S_FALSE;
  if (produced < _blockSize)
    memset(out + produced, 0, _blockSize - produced);
  return S_OK;
}

REGISTER_ARC_I(
  "ZSO", "zso", NULL, 0x97,
  kSignature,
  0,
  0,
  NULL)

}

// =============================================================================================
// ISZ (UltraISO): a header, an obfuscated table of 3-byte block entries (size + kind), blocks.

namespace NIsz {

using namespace NBlockImage;

static const Byte kSignature[] = { 'I', 's', 'Z', '!' };

class CHandler: public CBlockHandler
{
  CRecordVector<UInt32> _sizes;     // packed size of each block
  CRecordVector<Byte> _kinds;       // 0 zeros, 1 stored, 2 zlib, 3 bzip2
  CRecordVector<UInt64> _offsets;   // where each block starts in the file
  CByteBuffer _packed;

  HRESULT Open2(IInStream *stream, IArchiveOpenCallback *openCallback) Z7_override;
  HRESULT DecodeBlock(UInt64 block, Byte *out) Z7_override;
  void CloseFormat() Z7_override { _sizes.Clear(); _kinds.Clear(); _offsets.Clear(); _packed.Free(); }
};

HRESULT CHandler::Open2(IInStream *stream, IArchiveOpenCallback * /* openCallback */)
{
  Byte h[64];
  RINOK(ReadStream_FALSE(stream, h, sizeof(h)))
  if (memcmp(h, kSignature, 4) != 0)
    return S_FALSE;
  UInt64 fileSize = 0;
  RINOK(InStream_GetSize_SeekToEnd(stream, fileSize))
  const unsigned headerSize = h[4];
  const unsigned sectorSize = GetUi16(h + 10);
  const UInt32 totalSectors = GetUi32(h + 12);
  const unsigned password = h[16];
  const UInt64 segmentSize = GetUi64(h + 17);
  const UInt32 numBlocks = GetUi32(h + 25);
  _blockSize = GetUi32(h + 29);
  const unsigned ptrLen = h[33];
  const UInt32 ptrOffset = GetUi32(h + 35);
  const UInt32 segOffset = GetUi32(h + 39);
  const UInt32 dataOffset = GetUi32(h + 43);
  if (headerSize < 48 || sectorSize == 0 || _blockSize == 0 || _blockSize > (1 << 24) || dataOffset > fileSize)
    return S_FALSE;
  Stream = stream;
  _isArc = true;
  _phySize = fileSize;
  _imgExt = "iso";
  _method = "ISZ";
  _size = (UInt64)totalSectors * sectorSize;
  if (password != 0 || segOffset != 0 || (segmentSize != 0 && segmentSize < fileSize))
  {
    // Encrypted, or split into .i01 / .i02 ... segments.
    _unsupported = true;
    return S_OK;
  }
  if (ptrOffset == 0)
  {
    // No block table: the image is stored as it is after the header.
    const UInt64 n = (_size + _blockSize - 1) / _blockSize;
    UInt64 pos = dataOffset;
    for (UInt64 i = 0; i < n; i++, pos += _blockSize)
    {
      _sizes.Add(_blockSize);
      _kinds.Add(1);
      _offsets.Add(pos);
    }
    return S_OK;
  }
  if (ptrLen < 3 || ptrLen > 4 || numBlocks == 0 || numBlocks > (1 << 26)
      || ptrOffset + (UInt64)numBlocks * ptrLen > fileSize)
    return S_FALSE;
  CByteBuffer table((size_t)numBlocks * ptrLen);
  RINOK(InStream_SeekSet(stream, ptrOffset))
  RINOK(ReadStream_FALSE(stream, table, table.Size()))
  // The table is XORed with the bitwise NOT of "IsZ!".
  static const Byte kKey[4] = { 0xB6, 0x8C, 0xA5, 0xDE };
  for (size_t i = 0; i < table.Size(); i++)
    table[i] ^= kKey[i & 3];
  UInt64 pos = dataOffset;
  for (UInt32 i = 0; i < numBlocks; i++)
  {
    const Byte *e = table + (size_t)i * ptrLen;
    UInt32 v = (UInt32)e[0] | ((UInt32)e[1] << 8) | ((UInt32)e[2] << 16);
    if (ptrLen == 4)
      v |= (UInt32)e[3] << 24;
    const unsigned bits = ptrLen * 8;
    const UInt32 kind = v >> (bits - 2);
    const UInt32 size = v & (((UInt32)1 << (bits - 2)) - 1);
    _sizes.Add(size);
    _kinds.Add((Byte)kind);
    _offsets.Add(pos);
    if (kind != 0)
      pos += size;
  }
  return S_OK;
}

HRESULT CHandler::DecodeBlock(UInt64 block, Byte *out)
{
  if (block >= _sizes.Size())
    return S_FALSE;
  const unsigned i = (unsigned)block;
  const UInt32 size = _sizes[i];
  const UInt64 want = (block + 1) * _blockSize <= _size ? _blockSize : _size - block * _blockSize;
  switch (_kinds[i])
  {
    case 0:
      memset(out, 0, _blockSize);
      return S_OK;
    case 1:
    {
      memset(out, 0, _blockSize);
      RINOK(InStream_SeekSet(Stream, _offsets[i]))
      size_t n = size < _blockSize ? size : _blockSize;
      return ReadStream(Stream, out, &n);
    }
  }
  if (size == 0 || size > _blockSize * 2 + 1024)
    return S_FALSE;
  if (_packed.Size() < size)
    _packed.Alloc(size);
  RINOK(ReadAt(_offsets[i], _packed, size))
  size_t produced = 0;
  HRESULT res;
  if (_kinds[i] == 2)
    res = Inflate(_packed, size, out, _blockSize, true, produced);
  else
  {
    // UltraISO overwrites a bzip2 block's "BZh" magic; it is put back before decoding.
    if (size >= 3) { _packed[0] = 'B'; _packed[1] = 'Z'; _packed[2] = 'h'; }
    res = Bunzip2(_packed, size, out, _blockSize, produced);
  }
  if (produced < want)
    return res != S_OK ? res : S_FALSE;
  if (produced < _blockSize)
    memset(out + produced, 0, _blockSize - produced);
  return S_OK;
}

REGISTER_ARC_I(
  "ISZ", "isz", NULL, 0x98,
  kSignature,
  0,
  0,
  NULL)

}

// =============================================================================================
// zisofs (mkzftree): a file compressed in zlib blocks, as on a Rock Ridge "ZF" volume.

namespace NZisofs {

using namespace NBlockImage;

static const Byte kSignature[] = { 0x37, 0xE4, 0x53, 0x96, 0xC9, 0xDB, 0xD6, 0x07 };

class CHandler: public CBlockHandler
{
  CRecordVector<UInt32> _pointers;  // numBlocks + 1
  CByteBuffer _packed;

  HRESULT Open2(IInStream *stream, IArchiveOpenCallback *openCallback) Z7_override;
  HRESULT DecodeBlock(UInt64 block, Byte *out) Z7_override;
  void CloseFormat() Z7_override { _pointers.Clear(); _packed.Free(); }
};

HRESULT CHandler::Open2(IInStream *stream, IArchiveOpenCallback * /* openCallback */)
{
  Byte h[16];
  RINOK(ReadStream_FALSE(stream, h, sizeof(h)))
  if (memcmp(h, kSignature, 8) != 0)
    return S_FALSE;
  UInt64 fileSize = 0;
  RINOK(InStream_GetSize_SeekToEnd(stream, fileSize))
  _size = GetUi32(h + 8);
  const unsigned headerSize = (unsigned)h[12] * 4;
  const unsigned log2 = h[13];
  if (headerSize < 16 || log2 < 15 || log2 > 17)
    return S_FALSE;
  _blockSize = (UInt32)1 << log2;
  const UInt64 numBlocks = (_size + _blockSize - 1) / _blockSize;
  if (headerSize + (numBlocks + 1) * 4 > fileSize)
    return S_FALSE;
  CByteBuffer table((size_t)(numBlocks + 1) * 4);
  RINOK(InStream_SeekSet(stream, headerSize))
  RINOK(ReadStream_FALSE(stream, table, table.Size()))
  for (UInt64 i = 0; i <= numBlocks; i++)
    _pointers.Add(GetUi32(table + (size_t)i * 4));
  Stream = stream;
  _isArc = true;
  _phySize = fileSize;
  _method = "zisofs";
  return S_OK;
}

HRESULT CHandler::DecodeBlock(UInt64 block, Byte *out)
{
  if (block + 1 >= _pointers.Size())
    return S_FALSE;
  const UInt32 a = _pointers[(unsigned)block], b = _pointers[(unsigned)block + 1];
  if (b < a || b - a > _blockSize * 2 + 64)
    return S_FALSE;
  const UInt64 want = (block + 1) * _blockSize <= _size ? _blockSize : _size - block * _blockSize;
  if (a == b)
  {
    memset(out, 0, _blockSize);               // an all-zero block is not stored
    return S_OK;
  }
  const size_t packed = b - a;
  if (_packed.Size() < packed)
    _packed.Alloc(packed);
  RINOK(ReadAt(a, _packed, packed))
  size_t produced = 0;
  const HRESULT res = Inflate(_packed, packed, out, _blockSize, true, produced);
  if (produced < want)
    return res != S_OK ? res : S_FALSE;
  if (produced < _blockSize)
    memset(out + produced, 0, _blockSize - produced);
  return S_OK;
}

REGISTER_ARC_I(
  "zisofs", "zisofs", NULL, 0x99,
  kSignature,
  0,
  0,
  NULL)

}

}
