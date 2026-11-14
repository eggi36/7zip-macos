// ChdHandler.cpp -- CHD v3 / v4 (MAME's "Compressed Hunks of Data"; a macOS addition, after
// Iso7z, which reads v4). The data is cut into hunks, each deflated, stored, a repeated 8-byte
// value or a copy of another hunk. A CD image carries its track list as metadata (CHT2 / CHTR)
// and stores each frame as 2352 bytes of sector and 96 of subcode, tracks padded to 4 frames and
// audio big-endian; it is shown track by track like a cue sheet. Anything else (a hard disk) is
// one "image.img".

#include "StdAfx.h"

#include "DiscImage.h"
#include "CompressedImages.h"

#include "../../../C/CpuArch.h"

#include "../../../CPP/Common/MyBuffer.h"
#include "../../../CPP/Common/StringToInt.h"
#include "../../../CPP/7zip/Common/RegisterArc.h"
#include "../../../CPP/7zip/Common/StreamUtils.h"

namespace NArchive {
namespace NChd {

using namespace NDiscImage;

static const Byte kSignature[] = { 'M', 'C', 'o', 'm', 'p', 'r', 'H', 'D' };

static const UInt32 kFrameSize = kRawSize + kSubSize;     // 2448
static const unsigned kTrackPadding = 4;

struct CMapEntry
{
  UInt64 Offset;
  UInt32 Length;
  Byte Type;        // 1 compressed, 2 uncompressed, 3 mini, 4 self, 5 parent
};

// The logical bytes of the CHD, decompressed hunk by hunk.
Z7_CLASS_IMP_IInStream(
  CChdStream
)
  UInt64 _virtPos;
  CByteBuffer _hunk;
  CByteBuffer _packed;
  UInt32 _cached;
  HRESULT LoadHunk(UInt32 index, Byte *out, unsigned depth);
public:
  CMyComPtr<IInStream> Stream;
  CRecordVector<CMapEntry> Map;
  UInt32 HunkBytes;
  UInt64 LogicalBytes;
  bool Zlib;
  CChdStream(): _virtPos(0), _cached((UInt32)(Int32)-1), HunkBytes(0), LogicalBytes(0), Zlib(true) {}
};

HRESULT CChdStream::LoadHunk(UInt32 index, Byte *out, unsigned depth)
{
  if (index >= Map.Size() || depth > 4)
    return S_FALSE;
  const CMapEntry &e = Map[index];
  switch (e.Type)
  {
    case 1:
    {
      if (!Zlib || e.Length == 0 || e.Length > HunkBytes * 2 + 1024)
        return S_FALSE;
      if (_packed.Size() < e.Length)
        _packed.Alloc(e.Length);
      RINOK(InStream_SeekSet(Stream, e.Offset))
      RINOK(ReadStream_FALSE(Stream, _packed, e.Length))
      size_t produced = 0;
      const HRESULT res = NBlockImage::Inflate(_packed, e.Length, out, HunkBytes, false, produced);
      if (produced != HunkBytes)
        return res != S_OK ? res : S_FALSE;
      return S_OK;
    }
    case 2:
      RINOK(InStream_SeekSet(Stream, e.Offset))
      return ReadStream_FALSE(Stream, out, HunkBytes);
    case 3:
    {
      // the 8-byte value (big-endian, in the offset field) repeated over the hunk
      Byte v[8];
      SetBe64(v, e.Offset)
      for (UInt32 i = 0; i < HunkBytes; i++)
        out[i] = v[i & 7];
      return S_OK;
    }
    case 4:
      return LoadHunk((UInt32)e.Offset, out, depth + 1);
  }
  return S_FALSE;                     // a parent hunk (a diff CHD) or an unknown type
}

Z7_COM7F_IMF(CChdStream::Read(void *data, UInt32 size, UInt32 *processedSize))
{
  if (processedSize)
    *processedSize = 0;
  if (_virtPos >= LogicalBytes || size == 0)
    return S_OK;
  if (size > LogicalBytes - _virtPos)
    size = (UInt32)(LogicalBytes - _virtPos);
  const UInt32 hunk = (UInt32)(_virtPos / HunkBytes);
  const UInt32 within = (UInt32)(_virtPos - (UInt64)hunk * HunkBytes);
  if (hunk != _cached)
  {
    _cached = (UInt32)(Int32)-1;
    if (_hunk.Size() != HunkBytes)
      _hunk.Alloc(HunkBytes);
    RINOK(LoadHunk(hunk, _hunk, 0))
    _cached = hunk;
  }
  UInt32 rem = HunkBytes - within;
  if (size > rem)
    size = rem;
  memcpy(data, _hunk + within, size);
  _virtPos += size;
  if (processedSize)
    *processedSize = size;
  return S_OK;
}

Z7_COM7F_IMF(CChdStream::Seek(Int64 offset, UInt32 seekOrigin, UInt64 *newPosition))
{
  switch (seekOrigin)
  {
    case STREAM_SEEK_SET: break;
    case STREAM_SEEK_CUR: offset += (Int64)_virtPos; break;
    case STREAM_SEEK_END: offset += (Int64)LogicalBytes; break;
    default: return STG_E_INVALIDFUNCTION;
  }
  if (offset < 0)
    return HRESULT_WIN32_ERROR_NEGATIVE_SEEK;
  _virtPos = (UInt64)offset;
  if (newPosition)
    *newPosition = _virtPos;
  return S_OK;
}

class CHandler: public CDiscHandler
{
  HRESULT ParseImage(IInStream *stream, IArchiveOpenCallback *callback) Z7_override;
  const char *FormatName() const Z7_override { return _version == 3 ? "CHD v3" : "CHD v4"; }
  unsigned _version;
public:
  CHandler(): _version(4) {}
};

// "TRACK:1 TYPE:MODE1_RAW SUBTYPE:NONE FRAMES:1000 PREGAP:0 ..." -> the value of `key`
static bool Field(const AString &meta, const char *key, AString &value)
{
  const int pos = meta.Find(key);
  if (pos < 0)
    return false;
  value.Empty();
  for (unsigned i = (unsigned)pos + MyStringLen(key); i < meta.Len() && meta[i] != ' ' && meta[i] != 0; i++)
    value += meta[i];
  return true;
}

static bool TypeToTrack(const AString &type, CTrack &t)
{
  t.AudioKnown = true;
  t.Audio = false;
  if (type == "AUDIO")                         { t.Audio = true; t.SectorSize = kRawSize; t.SwapAudio = true; }
  else if (type == "MODE1" || type == "MODE1/2048") t.SectorSize = kCookedSize;
  else if (type == "MODE1_RAW" || type == "MODE1/2352") t.SectorSize = kRawSize;
  else if (type == "MODE2" || type == "MODE2/2336" || type == "MODE2_FORM_MIX") t.SectorSize = kMode2Size;
  else if (type == "MODE2_FORM1" || type == "MODE2/2048") t.SectorSize = kCookedSize;
  else if (type == "MODE2_FORM2" || type == "MODE2/2324") t.SectorSize = 2324;
  else if (type == "MODE2_RAW" || type == "MODE2/2352" || type == "CDI/2352") t.SectorSize = kRawSize;
  else
    return false;
  t.Stride = kFrameSize;
  return true;
}

HRESULT CHandler::ParseImage(IInStream *stream, IArchiveOpenCallback * /* callback */)
{
  Byte h[124];
  RINOK(InStream_SeekSet(stream, 0))
  RINOK(ReadStream_FALSE(stream, h, 16))
  if (memcmp(h, kSignature, 8) != 0)
    return S_FALSE;
  const UInt32 headerLength = GetBe32(h + 8);
  _version = GetBe32(h + 12);
  IsArc = true;
  if (_version < 3 || _version > 4)
  {
    // v1 / v2 are older still; v5 replaced the map and the codecs (LZMA, FLAC, Huffman, ...).
    Unsupported = true;
    return S_FALSE;
  }
  const UInt32 want = _version == 3 ? 120 : 108;
  if (headerLength != want)
    return S_FALSE;
  RINOK(ReadStream_FALSE(stream, h + 16, want - 16))
  const UInt32 flags = GetBe32(h + 16);
  const UInt32 compression = GetBe32(h + 20);
  const UInt32 totalHunks = GetBe32(h + 24);
  const UInt64 logicalBytes = GetBe64(h + 28);
  const UInt64 metaOffset = GetBe64(h + 36);
  const UInt32 hunkBytes = GetBe32(h + (_version == 3 ? 76 : 44));
  if ((flags & 1) != 0 || compression > 2)
  {
    Unsupported = true;                  // needs its parent CHD, or the A/V codec
    return S_FALSE;
  }
  UInt64 fileSize = 0;
  RINOK(InStream_GetSize_SeekToEnd(stream, fileSize))
  if (hunkBytes == 0 || hunkBytes > (1 << 24) || totalHunks == 0 || totalHunks > (1 << 26)
      || (UInt64)totalHunks * hunkBytes < logicalBytes || want + (UInt64)totalHunks * 16 > fileSize)
    return S_FALSE;

  CChdStream *chd = new CChdStream;
  CMyComPtr<IInStream> chdHolder = chd;
  chd->Stream = stream;
  chd->HunkBytes = hunkBytes;
  chd->LogicalBytes = logicalBytes;
  chd->Zlib = compression != 0;
  {
    CByteBuffer map((size_t)totalHunks * 16);
    RINOK(InStream_SeekSet(stream, want))
    RINOK(ReadStream_FALSE(stream, map, map.Size()))
    for (UInt32 i = 0; i < totalHunks; i++)
    {
      const Byte *m = map + (size_t)i * 16;
      CMapEntry e;
      e.Offset = GetBe64(m);
      e.Length = GetBe16(m + 12) | ((UInt32)m[14] << 16);
      e.Type = (Byte)(m[15] & 0x0F);
      chd->Map.Add(e);
    }
  }
  Sources.Add(chdHolder);

  // The CD track list, if any: the metadata chain, entries tagged CHT2 / CHTR.
  UInt64 meta = metaOffset;
  UInt32 frameOffset = 0;
  for (unsigned guard = 0; meta != 0 && guard < 256; guard++)
  {
    if (meta + 16 > fileSize)
      break;
    Byte mh[16];
    RINOK(InStream_SeekSet(stream, meta))
    RINOK(ReadStream_FALSE(stream, mh, 16))
    const UInt32 tag = GetBe32(mh);
    const UInt32 length = GetBe32(mh + 4) & 0xFFFFFF;
    meta = GetBe64(mh + 8);         // the next entry; set first, so a skipped entry advances too
    if (length < 4096 && (tag == 0x43485432 || tag == 0x43485452))     // 'CHT2', 'CHTR'
    {
      CByteBuffer text(length);
      RINOK(ReadStream_FALSE(stream, text, length))
      AString s;
      for (UInt32 i = 0; i < length && text[i] != 0; i++)
        s += (char)text[i];
      AString number, type, frames;
      if (Field(s, "TRACK:", number) && Field(s, "TYPE:", type) && Field(s, "FRAMES:", frames))
      {
        CTrack t;
        const char *end;
        t.Number = ConvertStringToUInt32(number, &end);
        const UInt32 n = ConvertStringToUInt32(frames, &end);
        if (!TypeToTrack(type, t))
        {
          Unsupported = true;
          continue;
        }
        t.SourceIndex = 0;
        t.Offset = (UInt64)frameOffset * kFrameSize;
        t.NumSectors = n;
        Tracks.Add(t);
        frameOffset += n + ((n + kTrackPadding - 1) / kTrackPadding * kTrackPadding - n);
      }
    }
  }
  if (Tracks.IsEmpty())
  {
    // Not a CD: the whole logical image as one file.
    CTrack t;
    t.Name = "image.img";
    t.SourceIndex = 0;
    t.Offset = 0;
    t.SectorSize = 512;
    t.Stride = 512;
    t.NumSectors = logicalBytes / 512;
    t.AudioKnown = true;
    Tracks.Add(t);
  }
  PhySize = fileSize;
  return S_OK;
}

REGISTER_ARC_I_CLS(
  CHandler(),
  "CHD", "chd", NULL, 0x9B,
  kSignature,
  0,
  0,
  NULL)

}}
