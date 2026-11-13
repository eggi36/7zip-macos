// DiscText.cpp -- disc images described by a text file next to the sector data (a macOS
// addition, after Iso7z): CUE/BIN (cue sheet), GDI (Dreamcast GD-ROM) and CCD/IMG (CloneCD).
// The descriptor is what 7-Zip opens; the data files are found next to it.

#include "StdAfx.h"

#include "DiscImage.h"

#include "../../../CPP/Common/StringConvert.h"
#include "../../../CPP/Common/StringToInt.h"
#include "../../../CPP/7zip/Common/RegisterArc.h"
#include "../../../CPP/7zip/Common/StreamUtils.h"

namespace NArchive {
namespace NDiscText {

using namespace NDiscImage;

static const size_t kMaxDescriptor = 1 << 20;

// The lines of a descriptor, without line ends.
static void SplitLines(const AString &text, AStringVector &lines)
{
  AString line;
  for (unsigned i = 0; i <= text.Len(); i++)
  {
    const char c = i < text.Len() ? text[i] : '\n';
    if (c == '\n' || c == '\r')
    {
      line.Trim();
      if (!line.IsEmpty())
        lines.Add(line);
      line.Empty();
    }
    else
      line += c;
  }
}

// Words of a line; a "quoted string" is one word.
static void SplitWords(const AString &line, AStringVector &words)
{
  AString w;
  bool quoted = false, any = false;
  for (unsigned i = 0; i <= line.Len(); i++)
  {
    const char c = i < line.Len() ? line[i] : ' ';
    if (c == '"')
    {
      quoted = !quoted;
      any = true;
      continue;
    }
    if (!quoted && (c == ' ' || c == '\t'))
    {
      if (any)
        words.Add(w);
      w.Empty();
      any = false;
      continue;
    }
    w += c;
    any = true;
  }
}

static bool ParseUInt(const AString &s, UInt32 &v)
{
  if (s.IsEmpty())
    return false;
  const char *end;
  if (s.Len() > 2 && s[0] == '0' && (s[1] == 'x' || s[1] == 'X'))
    v = ConvertHexStringToUInt32(s.Ptr(2), &end);
  else
    v = ConvertStringToUInt32(s, &end);
  return *end == 0;
}

static UString ToUnicode(const AString &s)
{
  return MultiByteToUnicodeString(s, CP_UTF8);
}

// "dir/name.bin" or "dir\name.bin" -> "name.bin"
static UString BaseName(const UString &path)
{
  int pos = -1;
  for (unsigned i = 0; i < path.Len(); i++)
    if (path[i] == '/' || path[i] == '\\')
      pos = (int)i;
  return path.Ptr((unsigned)(pos + 1));
}

// "game.ccd" -> "game" + ext
static UString ReplaceExtension(const UString &name, const char *ext)
{
  UString s = name;
  const int dot = s.ReverseFind_Dot();
  if (dot >= 0)
    s.DeleteFrom((unsigned)dot);
  s += ext;
  return s;
}

static UInt64 StreamSize(IInStream *s)
{
  UInt64 size = 0;
  if (InStream_GetSize_SeekToEnd(s, size) != S_OK)
    return 0;
  return size;
}

// =============================================================================================
// CUE/BIN

namespace NCue {

class CHandler: public CDiscHandler
{
  struct CEntry
  {
    CTrack Track;
    UInt32 StartFrame;   // INDEX 01 inside its file
    bool HasStart;
  };

  HRESULT ParseImage(IInStream *stream, IArchiveOpenCallback *callback) Z7_override;
  const char *FormatName() const Z7_override { return "CUE/BIN"; }
};

static bool TrackType(const AString &type, CTrack &t)
{
  AString s = type;
  s.MakeLower_Ascii();
  t.AudioKnown = true;
  t.Stride = 0;
  if (s == "audio")            { t.Audio = true;  t.SectorSize = kRawSize; }
  else if (s == "cdg")         { t.Audio = true;  t.SectorSize = kRawSize; t.Stride = kRawSize + kSubSize; }
  else if (s == "mode1/2048")  { t.Audio = false; t.SectorSize = kCookedSize; }
  else if (s == "mode1/2352")  { t.Audio = false; t.SectorSize = kRawSize; }
  else if (s == "mode2/2336")  { t.Audio = false; t.SectorSize = kMode2Size; }
  else if (s == "mode2/2352" || s == "cdi/2352") { t.Audio = false; t.SectorSize = kRawSize; }
  else if (s == "mode2/2048")  { t.Audio = false; t.SectorSize = kCookedSize; }
  else
    return false;
  if (t.Stride == 0)
    t.Stride = t.SectorSize;
  return true;
}

HRESULT CHandler::ParseImage(IInStream *stream, IArchiveOpenCallback *callback)
{
  AString text;
  RINOK(ReadSmallText(stream, kMaxDescriptor, text))
  AStringVector lines;
  SplitLines(text, lines);

  CObjectVector<CEntry> entries;
  int file = -1;              // Sources index of the current FILE, -1 if it could not be opened
  bool haveFile = false;
  bool fileIsBinary = true;
  UInt32 session = 1;
  bool any = false;

  for (unsigned i = 0; i < lines.Size(); i++)
  {
    AStringVector w;
    SplitWords(lines[i], w);
    if (w.IsEmpty())
      continue;
    AString key = w[0];
    key.MakeLower_Ascii();
    if (key == "rem")
    {
      if (w.Size() >= 3)
      {
        AString k2 = w[1];
        k2.MakeLower_Ascii();
        UInt32 v;
        if (k2 == "session" && ParseUInt(w[2], v) && v >= 1)
          session = v;
      }
      continue;
    }
    if (key == "file")
    {
      if (w.Size() < 2)
        return S_FALSE;
      any = true;
      haveFile = true;
      AString type ("binary");
      if (w.Size() >= 3)
        type = w[2];
      type.MakeLower_Ascii();
      fileIsBinary = (type == "binary" || type == "motorola");
      if (!fileIsBinary)
        Unsupported = true;    // WAVE / MP3 / AIFF audio files are not raw sectors
      const UString name = ToUnicode(w[1]);
      RINOK(AddVolume(callback, name, file))
      if (file < 0 && BaseName(name) != name)
      {
        MissingFile.Empty();
        RINOK(AddVolume(callback, BaseName(name), file))
      }
      continue;
    }
    if (key == "track")
    {
      if (!haveFile || w.Size() < 3)
        return S_FALSE;
      CEntry e;
      UInt32 number;
      if (!ParseUInt(w[1], number) || number == 0 || number > 99)
        return S_FALSE;
      e.Track.Number = number;
      e.Track.Session = session;
      if (!TrackType(w[2], e.Track))
      {
        Unsupported = true;
        continue;
      }
      e.Track.SourceIndex = file < 0 ? (unsigned)0xFFFF : (unsigned)file;
      e.StartFrame = 0;
      e.HasStart = false;
      if (!fileIsBinary)
        e.Track.SourceIndex = 0xFFFF;
      entries.Add(e);
      any = true;
      continue;
    }
    if (key == "index")
    {
      if (entries.IsEmpty() || w.Size() < 3)
        return S_FALSE;
      UInt32 idx, frames;
      if (!ParseUInt(w[1], idx) || !ParseMsf(w[2], frames))
        return S_FALSE;
      CEntry &e = entries.Back();
      if (idx == 1 || (idx == 0 && !e.HasStart))
      {
        e.StartFrame = frames;
        e.HasStart = true;
      }
      continue;
    }
    // PERFORMER, TITLE, CATALOG, FLAGS, ISRC, PREGAP, POSTGAP, SONGWRITER, CDTEXTFILE: no data.
    if (key == "performer" || key == "title" || key == "catalog" || key == "flags" || key == "isrc"
        || key == "pregap" || key == "postgap" || key == "songwriter" || key == "cdtextfile")
      continue;
    // Anything else: not a cue sheet.
    if (!any)
      return S_FALSE;
  }
  if (!any || entries.IsEmpty())
    return S_FALSE;
  IsArc = true;

  // Offsets and lengths, per data file: a track runs to the next track's INDEX 01 in the same
  // file, the last one to the end of the file.
  for (unsigned i = 0; i < entries.Size(); i++)
  {
    CEntry &e = entries[i];
    if (e.Track.SourceIndex >= Sources.Size())
      continue;
    const unsigned src = e.Track.SourceIndex;
    // the byte position of this track: the previous track of the same file plus its sectors
    UInt64 offset = (UInt64)e.StartFrame * e.Track.Stride;
    if (i > 0 && entries[i - 1].Track.SourceIndex == src)
    {
      const CEntry &p = entries[i - 1];
      offset = p.Track.Offset + (UInt64)(e.StartFrame - p.StartFrame) * p.Track.Stride;
    }
    e.Track.Offset = offset;
    UInt64 end;
    if (i + 1 < entries.Size() && entries[i + 1].Track.SourceIndex == src)
    {
      const CEntry &n = entries[i + 1];
      if (n.StartFrame < e.StartFrame)
        return S_FALSE;
      end = offset + (UInt64)(n.StartFrame - e.StartFrame) * e.Track.Stride;
    }
    else
      end = StreamSize(Sources[src]);
    e.Track.NumSectors = end > offset ? (end - offset) / e.Track.Stride : 0;
    Tracks.Add(e.Track);
  }
  return S_OK;
}

REGISTER_ARC_I_CLS_NO_SIG(
  CHandler(),
  "CUE", "cue", NULL, 0x90,
  0,
  NArcInfoFlags::kByExtOnlyOpen,
  NULL)

}

// =============================================================================================
// GDI (Dreamcast GD-ROM): "count" then "track lba type sectorsize file offset" per line.

namespace NGdi {

class CHandler: public CDiscHandler
{
  HRESULT ParseImage(IInStream *stream, IArchiveOpenCallback *callback) Z7_override;
  const char *FormatName() const Z7_override { return "GDI"; }
};

HRESULT CHandler::ParseImage(IInStream *stream, IArchiveOpenCallback *callback)
{
  AString text;
  RINOK(ReadSmallText(stream, kMaxDescriptor, text))
  AStringVector lines;
  SplitLines(text, lines);
  if (lines.Size() < 2)
    return S_FALSE;
  UInt32 count;
  if (!ParseUInt(lines[0], count) || count == 0 || count > 99 || lines.Size() < 1 + count)
    return S_FALSE;
  for (unsigned i = 1; i <= count; i++)
  {
    AStringVector w;
    SplitWords(lines[i], w);
    UInt32 number, lba, type, sectorSize, offset = 0;
    if (w.Size() < 5 || !ParseUInt(w[0], number) || !ParseUInt(w[1], lba) || !ParseUInt(w[2], type)
        || !ParseUInt(w[3], sectorSize) || (w.Size() >= 6 && !ParseUInt(w[5], offset)))
      return S_FALSE;
    if (sectorSize != kRawSize && sectorSize != kCookedSize && sectorSize != kMode2Size)
      return S_FALSE;
    IsArc = true;
    CTrack t;
    t.Number = number;
    // Tracks 1 and 2 are the low-density area (a normal CD); 3 on the high-density area.
    t.Session = number >= 3 ? 2 : 1;
    t.Audio = (type & 4) == 0;
    t.AudioKnown = true;
    t.SectorSize = sectorSize;
    t.Stride = sectorSize;
    t.Offset = offset;
    int src;
    RINOK(AddVolume(callback, ToUnicode(w[4]), src))
    if (src < 0)
      continue;
    t.SourceIndex = (unsigned)src;
    const UInt64 size = StreamSize(Sources[(unsigned)src]);
    t.NumSectors = size > offset ? (size - offset) / sectorSize : 0;
    Tracks.Add(t);
  }
  return S_OK;
}

REGISTER_ARC_I_CLS_NO_SIG(
  CHandler(),
  "GDI", "gdi", NULL, 0x91,
  0,
  NArcInfoFlags::kByExtOnlyOpen,
  NULL)

}

// =============================================================================================
// CCD/IMG (CloneCD): an INI file whose [Entry n] sections are the TOC; the .img next to it
// holds every sector raw (2352 bytes), the .sub the subchannels (not needed here).

namespace NCcd {

class CHandler: public CDiscHandler
{
  HRESULT ParseImage(IInStream *stream, IArchiveOpenCallback *callback) Z7_override;
  const char *FormatName() const Z7_override { return "CCD/IMG"; }
};

struct CTocEntry
{
  UInt32 Session;
  UInt32 Point;
  UInt32 Control;
  UInt32 Plba;
  int PlbaSigned;
};

HRESULT CHandler::ParseImage(IInStream *stream, IArchiveOpenCallback *callback)
{
  AString text;
  RINOK(ReadSmallText(stream, kMaxDescriptor, text))
  AStringVector lines;
  SplitLines(text, lines);
  if (lines.IsEmpty())
    return S_FALSE;
  {
    AString first = lines[0];
    first.MakeLower_Ascii();
    if (first != "[clonecd]")
      return S_FALSE;
  }
  IsArc = true;

  CObjectVector<CTocEntry> toc;
  bool inEntry = false;
  for (unsigned i = 1; i < lines.Size(); i++)
  {
    AString line = lines[i];
    if (line[0] == '[')
    {
      AString sec = line;
      sec.MakeLower_Ascii();
      inEntry = sec.IsPrefixedBy("[entry ");
      if (inEntry)
      {
        CTocEntry e;
        e.Session = 1; e.Point = 0; e.Control = 0; e.Plba = 0; e.PlbaSigned = 0;
        toc.Add(e);
      }
      continue;
    }
    if (!inEntry)
      continue;
    const int eq = line.Find('=');
    if (eq <= 0)
      continue;
    AString key = line.Left((unsigned)eq);
    AString val (line.Ptr((unsigned)eq + 1));
    key.Trim();
    val.Trim();
    key.MakeLower_Ascii();
    UInt32 v;
    CTocEntry &e = toc.Back();
    if (key == "plba")
    {
      // PLBA may be negative (-150 for a pregap), read as signed
      const bool neg = !val.IsEmpty() && val[0] == '-';
      AString digits;
      if (neg) digits = val.Ptr(1); else digits = val;
      if (!ParseUInt(digits, v))
        continue;
      e.PlbaSigned = neg ? -(int)v : (int)v;
      continue;
    }
    if (!ParseUInt(val, v))
      continue;
    if (key == "session") e.Session = v;
    else if (key == "point") e.Point = v;
    else if (key == "control") e.Control = v;
  }

  // The image: same name, .img (or .IMG).
  const UString name = ArchiveName(callback);
  int src;
  RINOK(AddVolume(callback, ReplaceExtension(name, ".img"), src))
  if (src < 0)
  {
    MissingFile.Empty();
    RINOK(AddVolume(callback, ReplaceExtension(name, ".IMG"), src))
  }
  if (src < 0)
    return S_OK;
  const UInt64 imgSize = StreamSize(Sources[(unsigned)src]);
  const UInt64 imgSectors = imgSize / kRawSize;

  // Track starts (points 1..99) and session ends (point 0xA2 = lead-out), in TOC order.
  for (unsigned i = 0; i < toc.Size(); i++)
  {
    const CTocEntry &e = toc[i];
    if (e.Point < 1 || e.Point > 99 || e.PlbaSigned < 0)
      continue;
    CTrack t;
    t.Number = e.Point;
    t.Session = e.Session;
    t.Audio = (e.Control & 4) == 0;
    t.AudioKnown = true;
    t.SectorSize = kRawSize;
    t.Stride = kRawSize;
    t.SourceIndex = (unsigned)src;
    t.Offset = (UInt64)(UInt32)e.PlbaSigned * kRawSize;
    // The end: the next track in the same session, else that session's lead-out.
    UInt64 end = imgSectors;
    UInt32 bestNext = 0xFFFFFFFF;
    for (unsigned k = 0; k < toc.Size(); k++)
    {
      const CTocEntry &o = toc[k];
      if (o.Session != e.Session || o.PlbaSigned <= e.PlbaSigned)
        continue;
      if ((o.Point >= 1 && o.Point <= 99) || o.Point == 0xA2)
        if ((UInt32)o.PlbaSigned < bestNext)
          bestNext = (UInt32)o.PlbaSigned;
    }
    if (bestNext != 0xFFFFFFFF && bestNext < end)
      end = bestNext;
    // A later session's sectors are stored after the earlier ones without the gap between
    // them, so an address past the image is taken from the end of the image instead.
    if ((UInt64)(UInt32)e.PlbaSigned >= imgSectors)
      continue;
    t.NumSectors = end > (UInt64)(UInt32)e.PlbaSigned ? end - (UInt64)(UInt32)e.PlbaSigned : 0;
    Tracks.Add(t);
  }
  return S_OK;
}

REGISTER_ARC_I_CLS_NO_SIG(
  CHandler(),
  "CCD", "ccd", NULL, 0x92,
  0,
  NArcInfoFlags::kByExtOnlyOpen,
  NULL)

}

}}
