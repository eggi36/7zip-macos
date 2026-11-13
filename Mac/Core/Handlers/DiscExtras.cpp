// DiscExtras.cpp -- the disc as its file systems address it (see DiscImage.h): every track at
// its disc address (LBA), one ISO per session of a multi-session disc, and the files of a CD-ROM
// XA file system that hold Form 2 sectors (Video CD, PlayStation), as Iso7z shows them.

#include "StdAfx.h"

#include "DiscImage.h"

#include "../../../C/CpuArch.h"

#include "../../../CPP/Common/MyBuffer.h"
#include "../../../CPP/7zip/Common/StreamUtils.h"

namespace NArchive {
namespace NDiscImage {

// Red Book: the first session's lead-out and the next lead-in and pregap take 11400 sectors,
// each later gap 6900.
static const UInt32 kFirstSessionGap = 11400;
static const UInt32 kSessionGap = 6900;

static const Byte kSync[12] = { 0, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0 };

// ---------------------------------------------------------------------------------------------
// addresses

void CDiscHandler::AssignLbas()
{
  UInt64 next = 0;
  UInt32 session = 0;
  unsigned gaps = 0;
  for (unsigned i = 0; i < Tracks.Size(); i++)
  {
    CTrack &t = Tracks[i];
    if (i > 0 && t.Session != session)
      next += (gaps++ == 0) ? kFirstSessionGap : kSessionGap;
    session = t.Session;
    if (!t.LbaKnown)
      t.Lba = next;
    next = t.Lba + t.NumSectors;
  }
}

int CDiscHandler::FindTrack(UInt64 lba) const
{
  for (unsigned i = 0; i < Tracks.Size(); i++)
  {
    const CTrack &t = Tracks[i];
    if (lba >= t.Lba && lba < t.Lba + t.NumSectors && t.SourceIndex < Sources.Size())
      return (int)i;
  }
  return -1;
}

HRESULT CDiscHandler::ReadUser(UInt64 lba, Byte *out)
{
  memset(out, 0, kCookedSize);
  const int ti = FindTrack(lba);
  if (ti < 0)
    return S_OK;
  const CTrack &t = Tracks[(unsigned)ti];
  if (t.Audio)
    return S_OK;
  IInStream *s = Sources[t.SourceIndex];
  const UInt64 base = t.Offset + (lba - t.Lba) * t.Stride;
  UInt64 at;
  switch (t.SectorSize)
  {
    case kCookedSize: at = base; break;
    case kMode2Size: at = base + 8; break;
    case kRawSize:
    {
      Byte head[16];
      RINOK(InStream_SeekSet(s, base))
      size_t n = 16;
      RINOK(ReadStream(s, head, &n))
      if (n < 16)
        return S_OK;
      at = base + (head[15] == 2 ? 24 : 16);
      break;
    }
    default:
      return S_OK;
  }
  RINOK(InStream_SeekSet(s, at))
  size_t n = kCookedSize;
  return ReadStream(s, out, &n);
}

static Byte Bcd(unsigned v) { return (Byte)(((v / 10) << 4) | (v % 10)); }

HRESULT CDiscHandler::ReadRaw(UInt64 lba, Byte *out)
{
  memset(out, 0, kRawSize);
  const int ti = FindTrack(lba);
  if (ti < 0)
    return S_FALSE;
  const CTrack &t = Tracks[(unsigned)ti];
  IInStream *s = Sources[t.SourceIndex];
  const UInt64 base = t.Offset + (lba - t.Lba) * t.Stride;
  if (t.SectorSize == kRawSize)
  {
    RINOK(InStream_SeekSet(s, base))
    size_t n = kRawSize;
    return ReadStream(s, out, &n);
  }
  if (t.SectorSize == kMode2Size)
  {
    // sync and header (MSF of the address, mode 2) put back in front of the stored 2336 bytes
    memcpy(out, kSync, 12);
    const UInt64 a = lba + 150;
    out[12] = Bcd((unsigned)(a / 4500));
    out[13] = Bcd((unsigned)((a / 75) % 60));
    out[14] = Bcd((unsigned)(a % 75));
    out[15] = 2;
    RINOK(InStream_SeekSet(s, base))
    size_t n = kMode2Size;
    return ReadStream(s, out + 16, &n);
  }
  return S_FALSE;
}

// ---------------------------------------------------------------------------------------------
// sessions

void CDiscHandler::BuildSessions()
{
  UInt32 maxSession = 0;
  for (unsigned i = 0; i < Tracks.Size(); i++)
    if (Tracks[i].Session > maxSession)
      maxSession = Tracks[i].Session;
  if (maxSession < 2)
    return;
  for (UInt32 s = 1; s <= maxSession; s++)
  {
    UInt64 end = 0;
    bool hasData = false;
    for (unsigned i = 0; i < Tracks.Size(); i++)
    {
      const CTrack &t = Tracks[i];
      if (t.Session > s || t.Audio)
        continue;
      if (t.Lba + t.NumSectors > end)
        end = t.Lba + t.NumSectors;
      if (t.Session == s)
        hasData = true;
    }
    if (!hasData)
      continue;
    CSessionIso si;
    si.Session = s;
    si.NumSectors = end;
    SessionIsos.Add(si);
  }
}

// ---------------------------------------------------------------------------------------------
// CD-ROM XA file systems

static const unsigned kMaxXaEntries = 100000;

HRESULT CDiscHandler::ParseXa()
{
  CByteBuffer sector(kCookedSize);
  for (unsigned ti = 0; ti < Tracks.Size(); ti++)
  {
    const CTrack &t = Tracks[ti];
    // a Mode 2 track (raw with mode 2, or stored without sync as 2336 bytes)
    if (t.Audio || !(t.SectorSize == kMode2Size || (t.SectorSize == kRawSize && (t.UserOffset == 24 || t.RawData))))
      continue;
    RINOK(ReadUser(t.Lba + 16, sector))
    if (sector[0] != 1 || memcmp(sector + 1, "CD001", 5) != 0)
      continue;
    CObjectVector<CXaFile> files;
    bool anyRaw = false;
    // breadth first over the directories: (extent, size, path)
    struct CDir { UInt32 Lba; UInt32 Size; AString Path; unsigned Depth; };
    CObjectVector<CDir> dirs;
    CRecordVector<UInt32> seen;
    {
      const Byte *root = sector + 156;
      CDir d;
      d.Lba = GetUi32(root + 2);
      d.Size = GetUi32(root + 10);
      d.Depth = 0;
      dirs.Add(d);
    }
    char prefix[16];
    {
      const UInt32 n = t.Number != 0 ? t.Number : ti + 1;
      prefix[0] = 'T'; prefix[1] = 'r'; prefix[2] = 'a'; prefix[3] = 'c'; prefix[4] = 'k';
      prefix[5] = (char)('0' + n / 10); prefix[6] = (char)('0' + n % 10); prefix[7] = 0;
    }
    for (unsigned di = 0; di < dirs.Size() && files.Size() < kMaxXaEntries; di++)
    {
      const CDir dir = dirs[di];
      if (seen.FindInSorted(dir.Lba) >= 0 || dir.Size > (1 << 24) || dir.Depth > 32)
        continue;
      seen.AddToUniqueSorted(dir.Lba);
      const UInt32 numSectors = (dir.Size + kCookedSize - 1) / kCookedSize;
      for (UInt32 k = 0; k < numSectors && files.Size() < kMaxXaEntries; k++)
      {
        RINOK(ReadUser((UInt64)dir.Lba + k, sector))
        unsigned pos = 0;
        while (pos + 34 <= kCookedSize)
        {
          const Byte *r = sector + pos;
          const unsigned len = r[0];
          if (len == 0)
            break;                         // the rest of this sector is padding
          if (len < 34 || pos + len > kCookedSize)
            break;
          pos += len;
          const unsigned nameLen = r[32];
          if (33 + nameLen > len)
            continue;
          if (nameLen == 1 && (r[33] == 0 || r[33] == 1))
            continue;                      // "." and ".."
          AString name;
          for (unsigned c = 0; c < nameLen; c++)
            name += (char)r[33 + c];
          const int semi = name.Find(';');
          if (semi >= 0)
            name.DeleteFrom((unsigned)semi);
          if (!name.IsEmpty() && name.Back() == '.')
            name.DeleteBack();
          AString path = dir.Path;
          if (!path.IsEmpty())
            path += '/';
          path += name;
          const UInt32 extent = GetUi32(r + 2);
          const UInt32 size = GetUi32(r + 10);
          const bool isDir = (r[25] & 2) != 0;
          // the XA system-use field: after the name (padded to even), 14 bytes, "XA" at +6
          const unsigned su = 33 + nameLen + ((nameLen & 1) == 0 ? 1 : 0);
          bool xa = false;
          unsigned attr = 0;
          if (su + 14 <= len && r[su + 6] == 'X' && r[su + 7] == 'A')
          {
            xa = true;
            attr = GetBe16(r + su + 4);
          }
          if (isDir)
          {
            CDir d;
            d.Lba = extent;
            d.Size = size;
            d.Path = path;
            d.Depth = dir.Depth + 1;
            dirs.Add(d);
            continue;
          }
          CXaFile f;
          f.Path = prefix;
          f.Path += '/';
          f.Path += path;
          f.Lba = extent;
          f.Length = size;
          // Form 2 (0x1000) or interleaved (0x2000): the raw sectors, as Windows shows them.
          f.Raw = xa && (attr & 0x3000) != 0;
          memset(f.Record, 0, sizeof(f.Record));
          if (xa)
            memcpy(f.Record, r + su, 14);
          if (f.Raw)
            anyRaw = true;
          files.Add(f);
        }
      }
    }
    if (!anyRaw)
      continue;                            // an ordinary ISO: Track NN.iso shows it fully
    for (unsigned i = 0; i < files.Size(); i++)
      XaFiles.Add(files[i]);
  }
  return S_OK;
}

// ---------------------------------------------------------------------------------------------
// items

void CDiscHandler::BuildItems()
{
  Items.Clear();
  for (unsigned i = 0; i < Tracks.Size(); i++)
  {
    CItem item = { 0, i };
    Items.Add(item);
  }
  for (unsigned i = 0; i < SessionIsos.Size(); i++)
  {
    CItem item = { 1, i };
    Items.Add(item);
  }
  for (unsigned i = 0; i < XaFiles.Size(); i++)
  {
    CItem item = { 2, i };
    Items.Add(item);
  }
}

UInt64 CDiscHandler::ItemSize(unsigned index) const
{
  if (index >= Items.Size())
    return 0;
  const CItem &item = Items[index];
  switch (item.Kind)
  {
    case 0: return Tracks[item.Index].ExposedSize();
    case 1: return SessionIsos[item.Index].NumSectors * kCookedSize;
    default: return XaFiles[item.Index].Size();
  }
}

// A session's ISO: 2048 bytes per disc address, from LBA 0.
class CSessionStream Z7_final:
  public IInStream,
  public CMyUnknownImp
{
  Z7_COM_UNKNOWN_IMP_1(IInStream)
  Z7_IFACE_COM7_IMP(ISequentialInStream)
  Z7_IFACE_COM7_IMP(IInStream)
  UInt64 _virtPos;
  Byte _sector[kCookedSize];
  UInt64 _cached;
public:
  CDiscHandler *Owner;
  CMyComPtr<IUnknown> OwnerRef;
  UInt64 Size;
  CSessionStream(): _virtPos(0), _cached((UInt64)(Int64)-1), Owner(NULL), Size(0) {}
};

Z7_COM7F_IMF(CSessionStream::Read(void *data, UInt32 size, UInt32 *processedSize))
{
  if (processedSize)
    *processedSize = 0;
  if (_virtPos >= Size || size == 0)
    return S_OK;
  if (size > Size - _virtPos)
    size = (UInt32)(Size - _virtPos);
  const UInt64 lba = _virtPos / kCookedSize;
  const UInt32 within = (UInt32)(_virtPos - lba * kCookedSize);
  if (lba != _cached)
  {
    _cached = (UInt64)(Int64)-1;
    RINOK(Owner->ReadUser(lba, _sector))
    _cached = lba;
  }
  UInt32 rem = kCookedSize - within;
  if (size > rem)
    size = rem;
  memcpy(data, _sector + within, size);
  _virtPos += size;
  if (processedSize)
    *processedSize = size;
  return S_OK;
}

Z7_COM7F_IMF(CSessionStream::Seek(Int64 offset, UInt32 seekOrigin, UInt64 *newPosition))
{
  switch (seekOrigin)
  {
    case STREAM_SEEK_SET: break;
    case STREAM_SEEK_CUR: offset += (Int64)_virtPos; break;
    case STREAM_SEEK_END: offset += (Int64)Size; break;
    default: return STG_E_INVALIDFUNCTION;
  }
  if (offset < 0)
    return HRESULT_WIN32_ERROR_NEGATIVE_SEEK;
  _virtPos = (UInt64)offset;
  if (newPosition)
    *newPosition = _virtPos;
  return S_OK;
}

// An XA file: plain (2048 bytes per sector, its length) or RIFF CDXA of raw sectors.
class CXaStream Z7_final:
  public IInStream,
  public CMyUnknownImp
{
  Z7_COM_UNKNOWN_IMP_1(IInStream)
  Z7_IFACE_COM7_IMP(ISequentialInStream)
  Z7_IFACE_COM7_IMP(IInStream)
  UInt64 _virtPos;
  Byte _sector[kRawSize];
  UInt64 _cached;
  Byte _header[kWavHeaderSize];
public:
  CDiscHandler *Owner;
  CMyComPtr<IUnknown> OwnerRef;
  CXaFile File;
  CXaStream(): _virtPos(0), _cached((UInt64)(Int64)-1), Owner(NULL) {}
  void Init()
  {
    if (!File.Raw)
      return;
    const UInt32 dataSize = File.NumSectors() * kRawSize;
    Byte *p = _header;
    memcpy(p, "RIFF", 4);          SetUi32(p + 4, dataSize + 36)
    memcpy(p + 8, "CDXAfmt ", 8);  SetUi32(p + 16, 16)
    memcpy(p + 20, File.Record, 14);
    p[34] = 0; p[35] = 0;
    memcpy(p + 36, "data", 4);     SetUi32(p + 40, dataSize)
  }
};

Z7_COM7F_IMF(CXaStream::Read(void *data, UInt32 size, UInt32 *processedSize))
{
  if (processedSize)
    *processedSize = 0;
  const UInt64 total = File.Size();
  if (_virtPos >= total || size == 0)
    return S_OK;
  if (size > total - _virtPos)
    size = (UInt32)(total - _virtPos);
  UInt64 pos = _virtPos;
  if (File.Raw)
  {
    if (pos < kWavHeaderSize)
    {
      UInt32 n = (UInt32)(kWavHeaderSize - pos);
      if (n > size)
        n = size;
      memcpy(data, _header + (size_t)pos, n);
      _virtPos += n;
      if (processedSize)
        *processedSize = n;
      return S_OK;
    }
    pos -= kWavHeaderSize;
  }
  const UInt32 unit = File.Raw ? kRawSize : kCookedSize;
  const UInt64 index = pos / unit;
  const UInt32 within = (UInt32)(pos - index * unit);
  if (index != _cached)
  {
    _cached = (UInt64)(Int64)-1;
    if (File.Raw)
    {
      const HRESULT res = Owner->ReadRaw((UInt64)File.Lba + index, _sector);
      if (res != S_OK && res != S_FALSE)
        return res;
    }
    else
      RINOK(Owner->ReadUser((UInt64)File.Lba + index, _sector))
    _cached = index;
  }
  UInt32 rem = unit - within;
  if (size > rem)
    size = rem;
  memcpy(data, _sector + within, size);
  _virtPos += size;
  if (processedSize)
    *processedSize = size;
  return S_OK;
}

Z7_COM7F_IMF(CXaStream::Seek(Int64 offset, UInt32 seekOrigin, UInt64 *newPosition))
{
  switch (seekOrigin)
  {
    case STREAM_SEEK_SET: break;
    case STREAM_SEEK_CUR: offset += (Int64)_virtPos; break;
    case STREAM_SEEK_END: offset += (Int64)File.Size(); break;
    default: return STG_E_INVALIDFUNCTION;
  }
  if (offset < 0)
    return HRESULT_WIN32_ERROR_NEGATIVE_SEEK;
  _virtPos = (UInt64)offset;
  if (newPosition)
    *newPosition = _virtPos;
  return S_OK;
}

HRESULT CreateExtraStream(CDiscHandler *handler, const CItem &item, ISequentialInStream **stream)
{
  *stream = NULL;
  if (item.Kind == 1)
  {
    CSessionStream *spec = new CSessionStream;
    CMyComPtr<ISequentialInStream> holder = spec;
    spec->Owner = handler;
    spec->OwnerRef = (IInArchive *)handler;
    spec->Size = handler->SessionIsos[item.Index].NumSectors * kCookedSize;
    *stream = holder.Detach();
    return S_OK;
  }
  CXaStream *spec = new CXaStream;
  CMyComPtr<ISequentialInStream> holder = spec;
  spec->Owner = handler;
  spec->OwnerRef = (IInArchive *)handler;
  spec->File = handler->XaFiles[item.Index];
  spec->Init();
  *stream = holder.Detach();
  return S_OK;
}

}}
