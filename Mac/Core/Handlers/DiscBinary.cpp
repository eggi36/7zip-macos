// DiscBinary.cpp -- disc images with a binary descriptor (a macOS addition, after Iso7z):
// MDS/MDF (Alcohol 120%), NRG (Nero Burning ROM) and CDI (DiscJuggler). The layouts follow the
// public descriptions the open-source readers use (libmirage, cdirip).

#include "StdAfx.h"

#include "DiscImage.h"

#include "../../../C/CpuArch.h"

#include "../../../CPP/Common/MyBuffer.h"
#include "../../../CPP/Common/StringConvert.h"
#include "../../../CPP/7zip/Common/RegisterArc.h"
#include "../../../CPP/7zip/Common/StreamUtils.h"

namespace NArchive {
namespace NDiscBinary {

using namespace NDiscImage;

static UInt64 StreamSize(IInStream *s)
{
  UInt64 size = 0;
  if (InStream_GetSize_SeekToEnd(s, size) != S_OK)
    return 0;
  return size;
}

static UString ReplaceExtension(const UString &name, const char *ext)
{
  UString s = name;
  const int dot = s.ReverseFind_Dot();
  if (dot >= 0)
    s.DeleteFrom((unsigned)dot);
  s += ext;
  return s;
}

// =============================================================================================
// MDS/MDF (Alcohol 120%, descriptor version 1.x)

namespace NMds {

static const Byte kSignature[] = { 'M','E','D','I','A',' ','D','E','S','C','R','I','P','T','O','R' };

class CHandler: public CDiscHandler
{
  HRESULT ParseImage(IInStream *stream, IArchiveOpenCallback *callback) Z7_override;
  const char *FormatName() const Z7_override { return "MDS/MDF"; }
};

HRESULT CHandler::ParseImage(IInStream *stream, IArchiveOpenCallback *callback)
{
  const UInt64 size = StreamSize(stream);
  if (size < 0x58 || size > (1 << 24))
    return S_FALSE;
  CByteBuffer buf((size_t)size);
  RINOK(InStream_SeekSet(stream, 0))
  RINOK(ReadStream_FALSE(stream, buf, (size_t)size))
  const Byte *p = buf;
  if (memcmp(p, kSignature, sizeof(kSignature)) != 0)
    return S_FALSE;
  IsArc = true;
  if (p[16] != 1)
  {
    // MDS 2.x (DAEMON Tools' MDX family) encrypts its descriptor.
    Unsupported = true;
    return S_FALSE;
  }
  const unsigned numSessions = GetUi16(p + 0x14);
  const UInt32 sessionsOffset = GetUi32(p + 0x50);
  if (numSessions == 0 || numSessions > 99 || sessionsOffset + (UInt64)numSessions * 0x18 > size)
    return S_FALSE;

  // The data file: the descriptor's footer names it ("*.mdf" = same name as the .mds).
  const UString archiveName = ArchiveName(callback);
  int src = -2;
  for (unsigned s = 0; s < numSessions; s++)
  {
    const Byte *sess = p + sessionsOffset + s * 0x18;
    const unsigned sessionNumber = GetUi16(sess + 0x08);
    const unsigned numBlocks = sess[0x0A];
    const UInt32 tracksOffset = GetUi32(sess + 0x14);
    if (tracksOffset + (UInt64)numBlocks * 0x50 > size)
      return S_FALSE;
    for (unsigned b = 0; b < numBlocks; b++)
    {
      const Byte *tb = p + tracksOffset + b * 0x50;
      const unsigned mode = tb[0x00];
      const unsigned subchannel = tb[0x01];
      const unsigned point = tb[0x04];
      if (point < 1 || point > 99)          // 0xA0..0xA2: TOC entries, not tracks
        continue;
      const UInt32 extraOffset = GetUi32(tb + 0x0C);
      const unsigned sectorSize = GetUi16(tb + 0x10);
      const UInt64 startOffset = GetUi64(tb + 0x28);
      const UInt32 startSector = GetUi32(tb + 0x24);
      const UInt32 footerOffset = GetUi32(tb + 0x34);
      UInt32 length = 0;
      if (extraOffset != 0 && extraOffset + 8 <= size)
        length = GetUi32(p + extraOffset + 4);

      if (src == -2)
      {
        UString dataName = ReplaceExtension(archiveName, ".mdf");
        if (footerOffset != 0 && footerOffset + 16 <= size)
        {
          const UInt32 nameOffset = GetUi32(p + footerOffset);
          const bool wide = GetUi32(p + footerOffset + 4) != 0;
          if (nameOffset != 0 && nameOffset < size)
          {
            UString n;
            if (wide)
            {
              for (UInt64 i = nameOffset; i + 1 < size; i += 2)
              {
                const wchar_t c = (wchar_t)GetUi16(p + i);
                if (c == 0)
                  break;
                n += c;
              }
            }
            else
            {
              AString a;
              for (UInt64 i = nameOffset; i < size && p[i] != 0; i++)
                a += (char)p[i];
              n = MultiByteToUnicodeString(a, CP_ACP);
            }
            if (!n.IsEmpty() && !n.IsPrefixedBy(L"*."))
              dataName = n;
            else if (n.IsPrefixedBy(L"*."))
              dataName = ReplaceExtension(archiveName, "") + n.Ptr(1);
          }
        }
        RINOK(AddVolume(callback, dataName, src))
        if (src < 0)
          return S_OK;
      }
      CTrack t;
      t.Number = point;
      t.Session = sessionNumber != 0 ? sessionNumber : s + 1;
      // mode 0xA9 (0xE9): audio; 0xAA mode 1; 0xAB/0xAC/0xAD mode 2
      if ((mode & 0x0F) == 9)
      {
        t.Audio = true;
        t.AudioKnown = true;
      }
      const unsigned sub = (subchannel != 0) ? kSubSize : 0;
      if (sectorSize <= sub)
        return S_FALSE;
      t.SectorSize = sectorSize - sub;
      t.Stride = sectorSize;
      t.SourceIndex = (unsigned)src;
      t.Offset = startOffset;
      t.Lba = startSector;
      t.LbaKnown = true;
      t.NumSectors = length;
      if (t.NumSectors == 0)
      {
        const UInt64 dataSize = StreamSize(Sources[(unsigned)src]);
        if (dataSize > startOffset)
          t.NumSectors = (dataSize - startOffset) / t.Stride;
      }
      Tracks.Add(t);
    }
  }
  return S_OK;
}

REGISTER_ARC_I_CLS(
  CHandler(),
  "MDS", "mds", NULL, 0x93,
  kSignature,
  0,
  0,
  NULL)

}

// =============================================================================================
// NRG (Nero): a chunk list at the end of the file, found through the "NER5" / "NERO" footer.

namespace NNrg {

class CHandler: public CDiscHandler
{
  HRESULT ParseImage(IInStream *stream, IArchiveOpenCallback *callback) Z7_override;
  const char *FormatName() const Z7_override { return _version2 ? "NRG v2" : "NRG v1"; }
  bool _version2;
public:
  CHandler(): _version2(true) {}
};

// The sector size of a TAO track's mode (ETNF / ETN2).
static UInt32 TaoSectorSize(UInt32 mode, bool &audio)
{
  audio = false;
  switch (mode)
  {
    case 0: case 2: return kCookedSize;      // Mode 1 / Mode 2 Form 1, 2048
    case 3: return kMode2Size;               // Mode 2, 2336
    case 7: audio = true; return kRawSize;   // audio
    case 6: case 0x0F: return kRawSize;      // raw data
    case 0x10: audio = true; return kRawSize + kSubSize;
    case 0x11: return kRawSize + kSubSize;
  }
  return 0;
}

HRESULT CHandler::ParseImage(IInStream *stream, IArchiveOpenCallback * /* callback */)
{
  const UInt64 size = StreamSize(stream);
  if (size < 12)
    return S_FALSE;
  Byte tail[12];
  RINOK(InStream_SeekSet(stream, size - 12))
  RINOK(ReadStream_FALSE(stream, tail, 12))
  UInt64 chunks;
  if (memcmp(tail, "NER5", 4) == 0)
  {
    _version2 = true;
    chunks = GetBe64(tail + 4);
  }
  else if (memcmp(tail + 4, "NERO", 4) == 0)
  {
    _version2 = false;
    chunks = GetBe32(tail + 8);
  }
  else
    return S_FALSE;
  if (chunks >= size)
    return S_FALSE;
  const UInt64 listSize = size - chunks;
  if (listSize > (1 << 24))
    return S_FALSE;
  CByteBuffer list((size_t)listSize);
  RINOK(InStream_SeekSet(stream, chunks))
  RINOK(ReadStream_FALSE(stream, list, (size_t)listSize))
  IsArc = true;
  Sources.Add(CMyComPtr<IInStream>(stream));

  CRecordVector<UInt32> sessionTracks;    // SINF: tracks per session, in order
  CObjectVector<CTrack> found;
  size_t pos = 0;
  while (pos + 8 <= listSize)
  {
    const Byte *c = list + pos;
    const UInt32 chunkSize = GetBe32(c + 4);
    if (pos + 8 + chunkSize > listSize)
      break;
    const Byte *d = c + 8;
    if (memcmp(c, "END!", 4) == 0)
      break;
    if (memcmp(c, "SINF", 4) == 0 && chunkSize >= 4)
      sessionTracks.Add(GetBe32(d));
    else if ((memcmp(c, "DAOX", 4) == 0 || memcmp(c, "DAOI", 4) == 0) && chunkSize >= 22)
    {
      const bool x = c[3] == 'X';
      const unsigned entry = x ? 42 : 30;
      const unsigned first = d[20], last = d[21];
      for (unsigned i = 0; first + i <= last && 22 + (i + 1) * entry <= chunkSize; i++)
      {
        const Byte *e = d + 22 + i * entry;
        const UInt32 sectorSize = GetBe16(e + 12);
        const unsigned mode = e[14];
        const UInt64 index1 = x ? GetBe64(e + 26) : GetBe32(e + 22);
        const UInt64 end = x ? GetBe64(e + 34) : GetBe32(e + 26);
        if (sectorSize == 0 || end < index1)
          continue;
        CTrack t;
        t.Number = first + i;
        t.Audio = (mode == 7 || mode == 0x10);
        t.AudioKnown = true;
        t.Stride = sectorSize;
        t.SectorSize = sectorSize == kRawSize + kSubSize ? kRawSize : sectorSize;
        t.Offset = index1;
        t.NumSectors = (end - index1) / sectorSize;
        found.Add(t);
      }
    }
    else if ((memcmp(c, "ETN2", 4) == 0 || memcmp(c, "ETNF", 4) == 0))
    {
      const bool v2 = c[3] == '2';
      const unsigned entry = v2 ? 32 : 20;
      for (unsigned i = 0; (i + 1) * entry <= chunkSize; i++)
      {
        const Byte *e = d + i * entry;
        const UInt64 offset = v2 ? GetBe64(e) : GetBe32(e);
        const UInt64 length = v2 ? GetBe64(e + 8) : GetBe32(e + 4);
        const UInt32 mode = v2 ? GetBe32(e + 16) : GetBe32(e + 8);
        const UInt32 lba = v2 ? GetBe32(e + 20) : GetBe32(e + 12);
        bool audio;
        const UInt32 stride = TaoSectorSize(mode, audio);
        if (stride == 0)
        {
          Unsupported = true;
          continue;
        }
        CTrack t;
        t.Number = found.Size() + 1;
        t.Audio = audio;
        t.AudioKnown = true;
        t.Stride = stride;
        t.SectorSize = stride == kRawSize + kSubSize ? kRawSize : stride;
        t.Offset = offset;
        t.Lba = lba;
        t.LbaKnown = true;
        t.NumSectors = length / stride;
        found.Add(t);
      }
    }
    pos += 8 + chunkSize;
  }
  // Sessions from SINF, in order.
  unsigned k = 0;
  for (unsigned s = 0; s < sessionTracks.Size(); s++)
    for (UInt32 n = 0; n < sessionTracks[s] && k < found.Size(); n++, k++)
      found[k].Session = s + 1;
  for (unsigned i = 0; i < found.Size(); i++)
    Tracks.Add(found[i]);
  return S_OK;
}

REGISTER_ARC_I_CLS_NO_SIG(
  CHandler(),
  "NRG", "nrg", NULL, 0x94,
  0,
  NArcInfoFlags::kByExtOnlyOpen,
  NULL)

}

// =============================================================================================
// CDI (DiscJuggler 2 / 3 / 3.5 / 4): the descriptor at the end, the tracks one after another.

namespace NCdi {

class CHandler: public CDiscHandler
{
  HRESULT ParseImage(IInStream *stream, IArchiveOpenCallback *callback) Z7_override;
  const char *FormatName() const Z7_override { return "CDI"; }
};

static const UInt32 kV2 = 0x80000004, kV3 = 0x80000005, kV35 = 0x80000006;
static const Byte kTrackMark[10] = { 0, 0, 1, 0, 0, 0, 0xFF, 0xFF, 0xFF, 0xFF };

// A cursor over the descriptor that fails (instead of reading past it) when it runs out.
struct CReader
{
  const Byte *P;
  size_t Size;
  size_t Pos;
  bool Bad;
  bool Skip(size_t n) { if (Pos + n > Size) { Bad = true; return false; } Pos += n; return true; }
  UInt32 U32() { if (Pos + 4 > Size) { Bad = true; return 0; } const UInt32 v = GetUi32(P + Pos); Pos += 4; return v; }
  unsigned U16() { if (Pos + 2 > Size) { Bad = true; return 0; } const unsigned v = GetUi16(P + Pos); Pos += 2; return v; }
  unsigned U8() { if (Pos + 1 > Size) { Bad = true; return 0; } return P[Pos++]; }
  bool Mark() { if (Pos + 10 > Size || memcmp(P + Pos, kTrackMark, 10) != 0) { Bad = true; return false; } Pos += 10; return true; }
};

HRESULT CHandler::ParseImage(IInStream *stream, IArchiveOpenCallback * /* callback */)
{
  const UInt64 size = StreamSize(stream);
  if (size < 8)
    return S_FALSE;
  Byte tail[8];
  RINOK(InStream_SeekSet(stream, size - 8))
  RINOK(ReadStream_FALSE(stream, tail, 8))
  const UInt32 version = GetUi32(tail);
  const UInt32 headerValue = GetUi32(tail + 4);
  if (version != kV2 && version != kV3 && version != kV35)
    return S_FALSE;
  const UInt64 header = (version == kV35) ? size - headerValue : headerValue;
  if (header >= size - 8 || size - header > (1 << 24))
    return S_FALSE;
  const size_t descSize = (size_t)(size - 8 - header);
  CByteBuffer desc(descSize);
  RINOK(InStream_SeekSet(stream, header))
  RINOK(ReadStream_FALSE(stream, desc, descSize))
  IsArc = true;
  Sources.Add(CMyComPtr<IInStream>(stream));

  CReader r = { desc, descSize, 0, false };
  const unsigned numSessions = r.U16();
  if (r.Bad || numSessions == 0 || numSessions > 99)
    return S_FALSE;
  UInt64 position = 0;        // the tracks' data: one after another from the start of the file
  UInt32 number = 0;
  for (unsigned s = 0; s < numSessions; s++)
  {
    const unsigned numTracks = r.U16();
    if (r.Bad)
      return S_FALSE;
    for (unsigned i = 0; i < numTracks; i++)
    {
      if (r.U32() != 0)
        r.Skip(8);                         // DiscJuggler 3.00.780 and later
      if (!r.Mark() || !r.Mark())
        return S_FALSE;
      r.Skip(4);
      const unsigned nameLength = r.U8();
      r.Skip(nameLength);
      r.Skip(11 + 4 + 4);
      if (r.U32() == 0x80000000)
        r.Skip(8);                         // DiscJuggler 4
      r.Skip(2);
      const UInt32 pregap = r.U32();
      const UInt32 length = r.U32();
      r.Skip(6);
      const UInt32 mode = r.U32();         // 0 audio, 1 mode 1, 2 mode 2
      r.Skip(12);
      const UInt32 startLba = r.U32();
      r.U32();                             // total length
      r.Skip(16);
      const UInt32 sectorType = r.U32();   // 0: 2048, 1: 2336, 2: 2352
      r.Skip(29);
      if (version != kV2)
      {
        r.Skip(5);
        if (r.U32() == 0xFFFFFFFF)
          r.Skip(78);                      // DiscJuggler 3.00.780 and later
      }
      if (r.Bad)
        return S_FALSE;
      UInt32 sectorSize;
      switch (sectorType)
      {
        case 0: sectorSize = kCookedSize; break;
        case 1: sectorSize = kMode2Size; break;
        case 2: sectorSize = kRawSize; break;
        default: Unsupported = true; return S_FALSE;
      }
      if (mode > 2)
      {
        Unsupported = true;
        return S_FALSE;
      }
      position += (UInt64)pregap * sectorSize;
      CTrack t;
      t.Number = ++number;
      t.Session = s + 1;
      t.Audio = (mode == 0);
      t.AudioKnown = true;
      t.SectorSize = sectorSize;
      t.Stride = sectorSize;
      t.Offset = position;
      t.Lba = startLba;
      t.LbaKnown = true;
      t.NumSectors = length;
      if (position + (UInt64)length * sectorSize > header)
        return S_FALSE;
      Tracks.Add(t);
      position += (UInt64)length * sectorSize;
    }
    // the session's trailer
    r.Skip(4 + 8);
    if (version != kV2)
      r.Skip(1);
  }
  return S_OK;
}

REGISTER_ARC_I_CLS_NO_SIG(
  CHandler(),
  "CDI", "cdi", NULL, 0x95,
  0,
  NArcInfoFlags::kByExtOnlyOpen,
  NULL)

}

}}
