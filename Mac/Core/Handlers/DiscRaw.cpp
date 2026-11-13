// DiscRaw.cpp -- two disc images without a descriptor (a macOS addition, after the user's request):
//
//   * BIN: a raw CD image (2352-byte sectors, optionally with 96 bytes of subchannel after each)
//     opened on its own, without its .cue. It starts with a CD sync pattern, so it is found by its
//     signature as well as by the .bin extension. Without a cue sheet nothing tells where tracks
//     start, so the whole file is one data track: "Track01.iso" (the user data, which 7-Zip opens
//     as ISO 9660 / UDF in turn) -- the data track of a game disc whose audio tracks follow it
//     reads as on the disc, the audio is not split off. Open the .cue for the track list.
//   * GCM: a Nintendo GameCube disc image (.gcm, or .iso as the rippers name it). Not ISO 9660:
//     a big-endian boot block with the magic 0xC2339F3D at 0x1C and a file system table (FST).
//     Shown as Dolphin extracts a disc: "files/..." (the FST's tree) and "sys/" (boot.bin, bi2.bin,
//     apploader.img, main.dol, fst.bin). Wii discs (magic 0x5D1C9EA3 at 0x18) are encrypted and
//     not opened. Layout after the public descriptions (YAGCD, Dolphin's DiscIO).

#include "StdAfx.h"

#include "DiscImage.h"

#include "../../../C/CpuArch.h"

#include "../../../CPP/Common/ComTry.h"
#include "../../../CPP/Common/MyBuffer.h"
#include "../../../CPP/Common/MyString.h"
#include "../../../CPP/Common/StringConvert.h"
#include "../../../CPP/Common/UTFConvert.h"
#include "../../../CPP/Windows/PropVariant.h"
#include "../../../CPP/7zip/Common/LimitedStreams.h"
#include "../../../CPP/7zip/Common/ProgressUtils.h"
#include "../../../CPP/7zip/Common/RegisterArc.h"
#include "../../../CPP/7zip/Common/StreamUtils.h"
#include "../../../CPP/7zip/Compress/CopyCoder.h"
#include "../../../CPP/7zip/Archive/Common/ItemNameUtils.h"

namespace NArchive {

// =============================================================================================
// BIN: a raw CD image without its cue sheet

namespace NRawBin {

using namespace NDiscImage;

static const Byte kSignature[12] = { 0, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0 };

class CHandler: public CDiscHandler
{
  HRESULT ParseImage(IInStream *stream, IArchiveOpenCallback *callback) Z7_override;
  const char *FormatName() const Z7_override { return "BIN"; }
};

HRESULT CHandler::ParseImage(IInStream *stream, IArchiveOpenCallback * /* callback */)
{
  UInt64 size = 0;
  RINOK(InStream_GetSize_SeekToEnd(stream, size))
  const UInt32 kWithSub = kRawSize + kSubSize;
  Byte buf[kWithSub + 12];
  if (size < sizeof(buf))
    return S_FALSE;
  RINOK(InStream_SeekSet(stream, 0))
  RINOK(ReadStream_FALSE(stream, buf, sizeof(buf)))
  if (memcmp(buf, kSignature, 12) != 0)
    return S_FALSE;
  UInt32 stride;
  if (memcmp(buf + kRawSize, kSignature, 12) == 0)
    stride = kRawSize;
  else if (memcmp(buf + kWithSub, kSignature, 12) == 0)
    stride = kWithSub;
  else
    return S_FALSE;
  const UInt64 numSectors = size / stride;
  if (numSectors < 17)              // an ISO 9660 volume descriptor lives in sector 16
    return S_FALSE;
  IsArc = true;
  Sources.Add(CMyComPtr<IInStream>(stream));
  CTrack t;
  t.Number = 1;
  t.Audio = false;
  t.AudioKnown = true;
  t.SectorSize = kRawSize;
  t.Stride = stride;
  t.Offset = 0;
  t.NumSectors = numSectors;
  t.Lba = 0;
  t.LbaKnown = true;
  Tracks.Add(t);
  PhySize = numSectors * stride;
  return S_OK;
}

REGISTER_ARC_I_CLS(
  CHandler(),
  "BIN", "bin", NULL, 0x9C,
  kSignature,
  0,
  0,
  NULL)

}

// =============================================================================================
// GCM: a Nintendo GameCube disc

namespace NGcm {

static const Byte kSignature[4] = { 0xC2, 0x33, 0x9F, 0x3D };
static const UInt32 kMagicOffset = 0x1C;
static const UInt32 kBootSize = 0x440;           // boot.bin: the disc header
static const UInt32 kBi2Offset = 0x440, kBi2Size = 0x2000;
static const UInt32 kApploaderOffset = 0x2440;
static const UInt32 kMaxFst = 1 << 26;

struct CItem
{
  AString Path;          // UTF-8 from the FST's Shift-JIS / ASCII names (taken byte for byte)
  UInt64 Offset;
  UInt64 Size;
  bool IsDir;
};

class CHandler Z7_final:
  public IInArchive,
  public IInArchiveGetStream,
  public CMyUnknownImp
{
  Z7_COM_UNKNOWN_IMP_2(IInArchive, IInArchiveGetStream)
  Z7_IFACE_COM7_IMP(IInArchive)
  Z7_IFACE_COM7_IMP(IInArchiveGetStream)

  CMyComPtr<IInStream> _stream;
  CObjectVector<CItem> _items;
  UInt64 _phySize;
  AString _gameName;
  AString _gameId;

  HRESULT Open2(IInStream *stream);
  void AddSys(const char *name, UInt64 offset, UInt64 size);
public:
  CHandler(): _phySize(0) {}
};

static const Byte kProps[] = { kpidPath, kpidIsDir, kpidSize, kpidOffset };
static const Byte kArcProps[] = { kpidComment, kpidVolumeName };

IMP_IInArchive_Props
IMP_IInArchive_ArcProps

void CHandler::AddSys(const char *name, UInt64 offset, UInt64 size)
{
  CItem &item = _items.AddNew();
  item.Path = "sys/";
  item.Path += name;
  item.Offset = offset;
  item.Size = size;
  item.IsDir = false;
}

static AString FixedString(const Byte *p, unsigned maxLen)
{
  AString s;
  for (unsigned i = 0; i < maxLen && p[i] != 0; i++)
    s += (char)p[i];
  return s;
}

HRESULT CHandler::Open2(IInStream *stream)
{
  UInt64 fileSize = 0;
  RINOK(InStream_GetSize_SeekToEnd(stream, fileSize))
  Byte boot[kBootSize];
  if (fileSize < kApploaderOffset + 0x20)
    return S_FALSE;
  RINOK(InStream_SeekSet(stream, 0))
  RINOK(ReadStream_FALSE(stream, boot, kBootSize))
  if (memcmp(boot + kMagicOffset, kSignature, 4) != 0)
    return S_FALSE;
  _gameId = FixedString(boot, 6);
  _gameName = FixedString(boot + 0x20, 0x3E0);

  const UInt32 dolOffset = GetBe32(boot + 0x420);
  const UInt32 fstOffset = GetBe32(boot + 0x424);
  const UInt32 fstSize = GetBe32(boot + 0x428);
  if (fstSize < 12 || fstSize > kMaxFst || (UInt64)fstOffset + fstSize > fileSize)
    return S_FALSE;

  CByteBuffer fst(fstSize);
  RINOK(InStream_SeekSet(stream, fstOffset))
  RINOK(ReadStream_FALSE(stream, fst, fstSize))
  const UInt32 numEntries = GetBe32(fst + 8);
  if ((fst[0] & 1) == 0 || numEntries == 0 || (UInt64)numEntries * 12 > fstSize)
    return S_FALSE;
  const Byte *names = fst + (size_t)numEntries * 12;
  const size_t namesSize = fstSize - (size_t)numEntries * 12;

  // sys/: what Dolphin's "Extract System Data" writes
  AddSys("boot.bin", 0, kBootSize);
  AddSys("bi2.bin", kBi2Offset, kBi2Size);
  {
    Byte a[0x20];
    RINOK(InStream_SeekSet(stream, kApploaderOffset))
    RINOK(ReadStream_FALSE(stream, a, sizeof(a)))
    const UInt64 size = 0x20 + (UInt64)GetBe32(a + 0x14) + GetBe32(a + 0x18);
    if (kApploaderOffset + size <= fileSize)
      AddSys("apploader.img", kApploaderOffset, size);
  }
  if (dolOffset != 0 && (UInt64)dolOffset + 0x100 <= fileSize)
  {
    Byte d[0x100];
    RINOK(InStream_SeekSet(stream, dolOffset))
    RINOK(ReadStream_FALSE(stream, d, sizeof(d)))
    UInt64 end = 0x100;
    for (unsigned i = 0; i < 18; i++)       // 7 text + 11 data sections: offsets at 0, sizes at 0x90
    {
      const UInt64 e = (UInt64)GetBe32(d + i * 4) + GetBe32(d + 0x90 + i * 4);
      if (GetBe32(d + 0x90 + i * 4) != 0 && e > end)
        end = e;
    }
    if (dolOffset + end <= fileSize)
      AddSys("main.dol", dolOffset, end);
  }
  AddSys("fst.bin", fstOffset, fstSize);

  // files/: the FST. A directory entry's "next" is one past its last child; the stack keeps the
  // open directories with their end index.
  struct CDir { UInt32 End; AString Path; };
  CObjectVector<CDir> stack;
  {
    CDir &root = stack.AddNew();
    root.End = numEntries;
    root.Path = "files";
  }
  {
    CItem &item = _items.AddNew();
    item.Path = "files";
    item.Offset = 0;
    item.Size = 0;
    item.IsDir = true;
  }
  for (UInt32 i = 1; i < numEntries; i++)
  {
    while (stack.Size() > 1 && i >= stack.Back().End)
      stack.DeleteBack();
    const Byte *e = fst + (size_t)i * 12;
    const UInt32 nameOffset = GetBe32(e) & 0xFFFFFF;
    if (nameOffset >= namesSize)
      return S_FALSE;
    AString name;
    for (size_t k = nameOffset; k < namesSize && names[k] != 0; k++)
      name += (char)names[k];
    if (name.IsEmpty() || name == "." || name == "..")
      return S_FALSE;
    name.Replace('/', '_');
    CItem &item = _items.AddNew();
    item.Path = stack.Back().Path;
    item.Path += '/';
    item.Path += name;
    if (e[0] & 1)
    {
      const UInt32 next = GetBe32(e + 8);
      if (next <= i || next > numEntries)
        return S_FALSE;
      item.IsDir = true;
      item.Offset = 0;
      item.Size = 0;
      CDir &dir = stack.AddNew();
      dir.End = next;
      dir.Path = item.Path;
    }
    else
    {
      item.IsDir = false;
      item.Offset = GetBe32(e + 4);
      item.Size = GetBe32(e + 8);
      if (item.Offset + item.Size > fileSize)
        return S_FALSE;
    }
  }
  _phySize = fileSize;            // a GameCube image is the whole disc (1 459 978 240 bytes), padding included
  return S_OK;
}

Z7_COM7F_IMF(CHandler::Open(IInStream *stream, const UInt64 *, IArchiveOpenCallback *))
{
  COM_TRY_BEGIN
  Close();
  const HRESULT res = Open2(stream);
  if (res != S_OK)
  {
    Close();
    return res;
  }
  _stream = stream;
  return S_OK;
  COM_TRY_END
}

Z7_COM7F_IMF(CHandler::Close())
{
  _stream.Release();
  _items.Clear();
  _phySize = 0;
  _gameName.Empty();
  _gameId.Empty();
  return S_OK;
}

Z7_COM7F_IMF(CHandler::GetNumberOfItems(UInt32 *numItems))
{
  *numItems = _items.Size();
  return S_OK;
}

Z7_COM7F_IMF(CHandler::GetArchiveProperty(PROPID propID, PROPVARIANT *value))
{
  COM_TRY_BEGIN
  NWindows::NCOM::CPropVariant prop;
  switch (propID)
  {
    case kpidPhySize: prop = _phySize; break;
    case kpidVolumeName: if (!_gameId.IsEmpty()) prop = _gameId; break;
    case kpidComment:
    {
      if (_gameName.IsEmpty())
        break;
      UString u;
      if (!ConvertUTF8ToUnicode(_gameName, u))
        u = MultiByteToUnicodeString(_gameName);
      prop = u;
      break;
    }
  }
  prop.Detach(value);
  return S_OK;
  COM_TRY_END
}

Z7_COM7F_IMF(CHandler::GetProperty(UInt32 index, PROPID propID, PROPVARIANT *value))
{
  COM_TRY_BEGIN
  NWindows::NCOM::CPropVariant prop;
  const CItem &item = _items[index];
  switch (propID)
  {
    case kpidPath:
    {
      UString u;
      if (!ConvertUTF8ToUnicode(item.Path, u))
        u = MultiByteToUnicodeString(item.Path);
      prop = NItemName::GetOsPath_Remove_TailSlash(u);
      break;
    }
    case kpidIsDir: prop = item.IsDir; break;
    case kpidSize:
    case kpidPackSize: if (!item.IsDir) prop = item.Size; break;
    case kpidOffset: if (!item.IsDir) prop = item.Offset; break;
  }
  prop.Detach(value);
  return S_OK;
  COM_TRY_END
}

Z7_COM7F_IMF(CHandler::GetStream(UInt32 index, ISequentialInStream **stream))
{
  COM_TRY_BEGIN
  *stream = NULL;
  if (index >= _items.Size() || !_stream)
    return E_FAIL;
  const CItem &item = _items[index];
  if (item.IsDir)
    return S_FALSE;
  return CreateLimitedInStream(_stream, item.Offset, item.Size, stream);
  COM_TRY_END
}

Z7_COM7F_IMF(CHandler::Extract(const UInt32 *indices, UInt32 numItems,
    Int32 testMode, IArchiveExtractCallback *extractCallback))
{
  COM_TRY_BEGIN
  const bool allFilesMode = (numItems == (UInt32)(Int32)-1);
  if (allFilesMode)
    numItems = _items.Size();
  if (numItems == 0)
    return S_OK;
  UInt64 totalSize = 0;
  for (UInt32 i = 0; i < numItems; i++)
  {
    const CItem &item = _items[allFilesMode ? i : indices[i]];
    if (!item.IsDir)
      totalSize += item.Size;
  }
  RINOK(extractCallback->SetTotal(totalSize))

  NCompress::CCopyCoderBase copyCoder;
  CMyComPtr2_Create<ICompressProgressInfo, CLocalProgress> lps;
  lps->Init(extractCallback, false);
  UInt64 size = 0;
  for (UInt32 i = 0;; i++, lps->InSize += size)
  {
    CLocalProgress *lps2 = lps.ClsPtr();
    lps2->OutSize = lps2->InSize;
    RINOK(lps2->SetCur())
    if (i >= numItems)
      break;
    const UInt32 index = allFilesMode ? i : indices[i];
    const CItem &item = _items[index];
    const Int32 askMode = testMode ? NExtract::NAskMode::kTest : NExtract::NAskMode::kExtract;
    CMyComPtr<ISequentialOutStream> outStream;
    RINOK(extractCallback->GetStream(index, &outStream, askMode))
    size = item.IsDir ? 0 : item.Size;
    if (item.IsDir)
    {
      RINOK(extractCallback->PrepareOperation(askMode))
      RINOK(extractCallback->SetOperationResult(NExtract::NOperationResult::kOK))
      continue;
    }
    if (!testMode && !outStream)
      continue;
    RINOK(extractCallback->PrepareOperation(askMode))
    Int32 opRes = NExtract::NOperationResult::kOK;
    CMyComPtr<ISequentialInStream> inStream;
    if (GetStream(index, &inStream) != S_OK || !inStream)
      opRes = NExtract::NOperationResult::kUnavailable;
    else
    {
      RINOK(copyCoder.Code(inStream, outStream, &size, lps))
      if (copyCoder.TotalSize != size)
        opRes = NExtract::NOperationResult::kUnexpectedEnd;
    }
    outStream.Release();
    RINOK(extractCallback->SetOperationResult(opRes))
  }
  return S_OK;
  COM_TRY_END
}

REGISTER_ARC_I(
  "GCM", "gcm iso", NULL, 0x9D,
  kSignature,
  kMagicOffset,
  0,
  NULL)

}

}
