// DiscImage.cpp -- see DiscImage.h

#include "StdAfx.h"

#include "DiscImage.h"

#include "../../../C/CpuArch.h"

#include "../../../CPP/Common/ComTry.h"
#include "../../../CPP/Common/IntToString.h"
#include "../../../CPP/Common/MyBuffer.h"
#include "../../../CPP/Common/StringConvert.h"
#include "../../../CPP/Windows/PropVariant.h"
#include "../../../CPP/7zip/Common/ProgressUtils.h"
#include "../../../CPP/7zip/Common/StreamUtils.h"
#include "../../../CPP/7zip/Compress/CopyCoder.h"

using namespace NWindows;

namespace NArchive {
namespace NDiscImage {

// ---------------------------------------------------------------------------------------------
// helpers

bool ParseMsf(const AString &s, UInt32 &frames)
{
  unsigned parts[3] = { 0, 0, 0 };
  unsigned n = 0;
  bool digit = false;
  for (unsigned i = 0; i < s.Len(); i++)
  {
    const char c = s[i];
    if (c >= '0' && c <= '9')
    {
      parts[n] = parts[n] * 10 + (unsigned)(c - '0');
      if (parts[n] > 100000)
        return false;
      digit = true;
    }
    else if (c == ':' && digit && n < 2)
    {
      n++;
      digit = false;
    }
    else
      return false;
  }
  if (n != 2 || !digit || parts[1] >= 60 || parts[2] >= 75)
    return false;
  frames = (UInt32)((parts[0] * 60 + parts[1]) * 75 + parts[2]);
  return true;
}

HRESULT ReadSmallText(IInStream *stream, size_t maxSize, AString &text)
{
  UInt64 size = 0;
  RINOK(InStream_GetSize_SeekToEnd(stream, size))
  if (size == 0 || size > maxSize)
    return S_FALSE;
  RINOK(InStream_SeekSet(stream, 0))
  CByteBuffer buf((size_t)size);
  RINOK(ReadStream_FALSE(stream, buf, (size_t)size))
  // A descriptor is text: no NUL bytes (that also rules out binary files with the extension).
  text.Empty();
  for (size_t i = 0; i < (size_t)size; i++)
  {
    const char c = (char)buf[i];
    if (c == 0)
      return S_FALSE;
    text += c;
  }
  return S_OK;
}

// ---------------------------------------------------------------------------------------------
// the stream of one track

Z7_CLASS_IMP_IInStream(
  CTrackStream
)
  UInt64 _virtPos;
  Byte _wavHeader[kWavHeaderSize];
public:
  CMyComPtr<IInStream> Source;
  CTrack Track;

  void Init()
  {
    _virtPos = 0;
    if (Track.Audio)
    {
      // RIFF / WAVE, PCM, 2 channels, 44100 Hz, 16 bit -- the Red Book format of a CD frame.
      const UInt32 dataSize = (UInt32)(Track.NumSectors * Track.UserSize);
      Byte *p = _wavHeader;
      memcpy(p, "RIFF", 4);           SetUi32(p + 4, dataSize + 36)
      memcpy(p + 8, "WAVEfmt ", 8);   SetUi32(p + 16, 16)
      SetUi16(p + 20, 1)              SetUi16(p + 22, 2)
      SetUi32(p + 24, 44100)          SetUi32(p + 28, 44100 * 4)
      SetUi16(p + 32, 4)              SetUi16(p + 34, 16)
      memcpy(p + 36, "data", 4);      SetUi32(p + 40, dataSize)
    }
  }
};

Z7_COM7F_IMF(CTrackStream::Read(void *data, UInt32 size, UInt32 *processedSize))
{
  if (processedSize)
    *processedSize = 0;
  const UInt64 total = Track.ExposedSize();
  if (_virtPos >= total || size == 0)
    return S_OK;
  if (size > total - _virtPos)
    size = (UInt32)(total - _virtPos);
  UInt64 pos = _virtPos;
  if (Track.Audio)
  {
    if (pos < kWavHeaderSize)
    {
      UInt32 n = (UInt32)(kWavHeaderSize - pos);
      if (n > size)
        n = size;
      memcpy(data, _wavHeader + (size_t)pos, n);
      _virtPos += n;
      if (processedSize)
        *processedSize = n;
      return S_OK;
    }
    pos -= kWavHeaderSize;
  }
  const UInt64 sector = pos / Track.UserSize;
  UInt32 within = (UInt32)(pos - sector * Track.UserSize);
  UInt32 rem = Track.UserSize - within;
  if (size > rem)
    size = rem;
  if (Track.SwapAudio)
  {
    // Whole 16-bit samples: from the even byte at or before `within`, at most one sector.
    Byte buf[kRawSize];
    const UInt32 start = within & ~(UInt32)1;
    const UInt32 len = ((within + size + 1) & ~(UInt32)1) - start;
    RINOK(InStream_SeekSet(Source, Track.Offset + sector * Track.Stride + Track.UserOffset + start))
    size_t got = len;
    RINOK(ReadStream(Source, buf, &got))
    if (got < len)
      memset(buf + got, 0, len - got);
    for (UInt32 i = 0; i + 1 < len; i += 2)
    {
      const Byte t = buf[i];
      buf[i] = buf[i + 1];
      buf[i + 1] = t;
    }
    memcpy(data, buf + (within - start), size);
    _virtPos += size;
    if (processedSize)
      *processedSize = size;
    return S_OK;
  }
  const UInt64 phys = Track.Offset + sector * Track.Stride + Track.UserOffset + within;
  RINOK(InStream_SeekSet(Source, phys))
  UInt32 got = 0;
  RINOK(Source->Read(data, size, &got))
  if (got == 0)
  {
    // The image ends before the track does (a truncated rip): the rest reads as zeros.
    memset(data, 0, size);
    got = size;
  }
  _virtPos += got;
  if (processedSize)
    *processedSize = got;
  return S_OK;
}

Z7_COM7F_IMF(CTrackStream::Seek(Int64 offset, UInt32 seekOrigin, UInt64 *newPosition))
{
  switch (seekOrigin)
  {
    case STREAM_SEEK_SET: break;
    case STREAM_SEEK_CUR: offset += (Int64)_virtPos; break;
    case STREAM_SEEK_END: offset += (Int64)Track.ExposedSize(); break;
    default: return STG_E_INVALIDFUNCTION;
  }
  if (offset < 0)
    return HRESULT_WIN32_ERROR_NEGATIVE_SEEK;
  _virtPos = (UInt64)offset;
  if (newPosition)
    *newPosition = _virtPos;
  return S_OK;
}

// ---------------------------------------------------------------------------------------------
// the handler

static const Byte kProps[] = { kpidPath, kpidSize, kpidPackSize, kpidComment };
static const Byte kArcProps[] = { kpidMethod, kpidNumBlocks };

#define CHandler CDiscHandler
IMP_IInArchive_Props
IMP_IInArchive_ArcProps
#undef CHandler

UString CDiscHandler::ArchiveName(IArchiveOpenCallback *callback)
{
  UString name;
  CMyComPtr<IArchiveOpenVolumeCallback> volumes;
  if (callback)
    callback->QueryInterface(IID_IArchiveOpenVolumeCallback, (void **)&volumes);
  if (volumes)
  {
    NCOM::CPropVariant prop;
    if (volumes->GetProperty(kpidName, &prop) == S_OK && prop.vt == VT_BSTR)
      name = prop.bstrVal;
  }
  return name;
}

// A FILE name of a cue / gdi / ccd sheet stays inside the sheet's folder: an absolute path, a
// drive letter or a ".." component is reduced to its last component (the file next to the sheet,
// where rippers put it), so a downloaded sheet cannot list a private file elsewhere as a track.
static UString ConfinedName(const UString &name)
{
  bool unsafe = name.IsEmpty() || name[0] == L'/' || name[0] == L'\\' || (name.Len() >= 2 && name[1] == L':');
  unsigned start = 0;
  for (unsigned i = 0; i <= name.Len() && !unsafe; i++)
    if (i == name.Len() || name[i] == L'/' || name[i] == L'\\')
    {
      if (i - start == 2 && name[start] == L'.' && name[start + 1] == L'.')
        unsafe = true;
      start = i + 1;
    }
  if (!unsafe)
    return name;
  int slash = -1;
  for (unsigned i = 0; i < name.Len(); i++)
    if (name[i] == L'/' || name[i] == L'\\')
      slash = (int)i;
  UString base = name.Ptr((unsigned)(slash + 1));
  if (base.Len() >= 2 && base[1] == L':')
    base.DeleteFrontal(2);
  if (base == L".." || base == L".")
    base.Empty();
  return base;
}

HRESULT CDiscHandler::AddVolume(IArchiveOpenCallback *callback, const UString &requested, int &index)
{
  index = -1;
  const UString name = ConfinedName(requested);
  if (name.IsEmpty())
  {
    if (MissingFile.IsEmpty())
      MissingFile = UnicodeStringToMultiByte(requested, CP_UTF8);
    return S_OK;
  }
  // Already open (several tracks in one .bin)?
  for (unsigned i = 0; i < _volumeNames.Size(); i++)
    if (_volumeNames[i].IsEqualTo_NoCase(name))
    {
      index = (int)i;
      return S_OK;
    }
  CMyComPtr<IArchiveOpenVolumeCallback> volumes;
  if (callback)
    callback->QueryInterface(IID_IArchiveOpenVolumeCallback, (void **)&volumes);
  if (!volumes)
    return S_OK;
  CMyComPtr<IInStream> stream;
  const HRESULT res = volumes->GetStream(name, &stream);
  if (res == S_FALSE || !stream)
  {
    if (MissingFile.IsEmpty())
      MissingFile = UnicodeStringToMultiByte(name, CP_UTF8);
    return S_OK;
  }
  RINOK(res)
  index = (int)Sources.Size();
  Sources.Add(stream);
  _volumeNames.Add(name);
  return S_OK;
}

HRESULT CDiscHandler::FinishTracks()
{
  for (unsigned i = 0; i < Tracks.Size(); i++)
  {
    CTrack &t = Tracks[i];
    if (t.Stride < t.SectorSize)
      t.Stride = t.SectorSize;
    t.RawData = false;
    if (t.SectorSize == kCookedSize)
    {
      t.Audio = false;
      t.UserOffset = 0;
      t.UserSize = kCookedSize;
      continue;
    }
    if (t.SectorSize == kMode2Size)
    {
      // Mode 2 without sync and header: an 8-byte subheader, then Form 1's 2048 bytes.
      t.Audio = false;
      t.UserOffset = 8;
      t.UserSize = kCookedSize;
      continue;
    }
    if (t.SectorSize != kRawSize)
    {
      t.RawData = true;
      t.UserOffset = 0;
      t.UserSize = t.SectorSize;
      continue;
    }
    // A raw 2352-byte track: audio, or a data track whose sync and mode say where its data is.
    Byte head[24];
    bool haveHead = false;
    if (t.SourceIndex < Sources.Size() && t.NumSectors != 0)
    {
      IInStream *s = Sources[t.SourceIndex];
      if (InStream_SeekSet(s, t.Offset) == S_OK)
      {
        size_t n = sizeof(head);
        if (ReadStream(s, head, &n) == S_OK && n == sizeof(head))
          haveHead = true;
      }
    }
    static const Byte kSync[12] = { 0, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0 };
    const bool sync = haveHead && memcmp(head, kSync, 12) == 0;
    if (!t.AudioKnown)
      t.Audio = !sync;
    if (t.Audio)
    {
      t.UserOffset = 0;
      t.UserSize = kRawSize;
      continue;
    }
    if (sync && head[15] == 1)
    {
      t.UserOffset = 16;                // Mode 1: 12 sync + 4 header
      t.UserSize = kCookedSize;
    }
    else if (sync && head[15] == 2)
    {
      t.UserOffset = 24;                // Mode 2 (XA): + 8 subheader; Form 1 holds 2048 bytes
      t.UserSize = kCookedSize;
      if ((head[18] & 0x20) != 0)       // Form 2 (video / audio streams): 2324 bytes, raw
      {
        t.UserOffset = 0;
        t.UserSize = kRawSize;
        t.RawData = true;
      }
    }
    else
    {
      t.UserOffset = 0;
      t.UserSize = kRawSize;
      t.RawData = true;
    }
  }
  return S_OK;
}

Z7_COM7F_IMF(CDiscHandler::Open(IInStream *stream, const UInt64 * /* maxCheckStartPosition */,
    IArchiveOpenCallback *callback))
{
  COM_TRY_BEGIN
  Close();
  const HRESULT res = ParseImage(stream, callback);
  if (res != S_OK)
  {
    const bool keep = IsArc && res == S_FALSE && !Tracks.IsEmpty();
    if (!keep)
    {
      Close();
      return res;
    }
  }
  if (Tracks.IsEmpty())
  {
    // The descriptor was read, but its data file is missing: a clear error, not "no archive".
    if (IsArc && !MissingFile.IsEmpty())
      return S_OK;
    Close();
    return S_FALSE;
  }
  IsArc = true;
  RINOK(FinishTracks())
  AssignLbas();
  BuildSessions();
  RINOK(ParseXa())
  BuildItems();
  if (PhySize == 0)
    RINOK(InStream_GetSize_SeekToEnd(stream, PhySize))
  return S_OK;
  COM_TRY_END
}

Z7_COM7F_IMF(CDiscHandler::Close())
{
  Sources.Clear();
  _volumeNames.Clear();
  Tracks.Clear();
  XaFiles.Clear();
  SessionIsos.Clear();
  Items.Clear();
  PhySize = 0;
  IsArc = false;
  Unsupported = false;
  MissingFile.Empty();
  return S_OK;
}

Z7_COM7F_IMF(CDiscHandler::GetNumberOfItems(UInt32 *numItems))
{
  *numItems = Items.Size();
  return S_OK;
}

static void TrackName(const CTrack &t, unsigned index, AString &s)
{
  if (!t.Name.IsEmpty())
  {
    s = t.Name;
    return;
  }
  char temp[16];
  s = "Track";
  const UInt32 n = t.Number != 0 ? t.Number : (UInt32)index + 1;
  if (n < 10)
    s += '0';
  ConvertUInt32ToString(n, temp);
  s += temp;
  s += t.Audio ? ".wav" : (t.RawData ? ".bin" : ".iso");
}

Z7_COM7F_IMF(CDiscHandler::GetProperty(UInt32 index, PROPID propID, PROPVARIANT *value))
{
  COM_TRY_BEGIN
  NCOM::CPropVariant prop;
  if (index >= Items.Size())
    return E_INVALIDARG;
  const CItem &item = Items[index];
  if (item.Kind == 1)
  {
    const CSessionIso &si = SessionIsos[item.Index];
    switch (propID)
    {
      case kpidPath:
      {
        char temp[16];
        AString s ("Session");
        ConvertUInt32ToString(si.Session, temp);
        s += temp;
        s += ".iso";
        prop = s;
        break;
      }
      case kpidSize: prop = ItemSize(index); break;
      case kpidComment: prop = "The disc up to the end of this session"; break;
    }
    prop.Detach(value);
    return S_OK;
  }
  if (item.Kind == 2)
  {
    const CXaFile &f = XaFiles[item.Index];
    switch (propID)
    {
      case kpidPath: prop = f.Path; break;
      case kpidSize: prop = f.Size(); break;
      case kpidComment: if (f.Raw) prop = "CD-ROM XA (RIFF CDXA, raw sectors)"; break;
    }
    prop.Detach(value);
    return S_OK;
  }
  const CTrack &t = Tracks[item.Index];
  switch (propID)
  {
    case kpidPath:
    {
      AString s;
      TrackName(t, item.Index, s);
      prop = s;
      break;
    }
    case kpidSize: prop = t.ExposedSize(); break;
    case kpidPackSize: prop = t.PackedSize(); break;
    case kpidComment:
    {
      AString s (t.Audio ? "Audio" : (t.RawData ? "Data (raw sectors)" : (t.UserOffset == 16 ? "Mode 1" : (t.UserOffset == 0 ? "Data" : "Mode 2 Form 1"))));
      if (t.Session > 1)
      {
        char temp[16];
        ConvertUInt32ToString(t.Session, temp);
        s += ", session ";
        s += temp;
      }
      prop = s;
      break;
    }
  }
  prop.Detach(value);
  return S_OK;
  COM_TRY_END
}

Z7_COM7F_IMF(CDiscHandler::GetArchiveProperty(PROPID propID, PROPVARIANT *value))
{
  COM_TRY_BEGIN
  NCOM::CPropVariant prop;
  switch (propID)
  {
    case kpidPhySize: if (PhySize != 0) prop = PhySize; break;
    case kpidMethod: prop = FormatName(); break;
    case kpidNumBlocks: prop = (UInt32)Tracks.Size(); break;
    case kpidErrorFlags:
    {
      UInt32 v = 0;
      if (!IsArc) v |= kpv_ErrorFlags_IsNotArc;
      if (Unsupported) v |= kpv_ErrorFlags_UnsupportedMethod;
      if (!MissingFile.IsEmpty()) v |= kpv_ErrorFlags_UnexpectedEnd;
      if (v != 0)
        prop = v;
      break;
    }
    case kpidError:
      if (!MissingFile.IsEmpty())
      {
        AString s ("Missing file: ");
        s += MissingFile;
        prop = s;
      }
      break;
  }
  prop.Detach(value);
  return S_OK;
  COM_TRY_END
}

Z7_COM7F_IMF(CDiscHandler::GetStream(UInt32 index, ISequentialInStream **stream))
{
  COM_TRY_BEGIN
  *stream = NULL;
  if (index >= Items.Size())
    return E_INVALIDARG;
  const CItem &item = Items[index];
  if (item.Kind != 0)
    return CreateExtraStream(this, item, stream);
  const CTrack &t = Tracks[item.Index];
  if (t.SourceIndex >= Sources.Size())
    return S_FALSE;
  CTrackStream *spec = new CTrackStream;
  CMyComPtr<ISequentialInStream> holder = spec;
  spec->Source = Sources[t.SourceIndex];
  spec->Track = t;
  spec->Init();
  *stream = holder.Detach();
  return S_OK;
  COM_TRY_END
}

Z7_COM7F_IMF(CDiscHandler::Extract(const UInt32 *indices, UInt32 numItems,
    Int32 testMode, IArchiveExtractCallback *extractCallback))
{
  COM_TRY_BEGIN
  const bool allFilesMode = (numItems == (UInt32)(Int32)-1);
  if (allFilesMode)
    numItems = Items.Size();
  if (numItems == 0)
    return S_OK;
  UInt64 totalSize = 0;
  for (UInt32 i = 0; i < numItems; i++)
  {
    const UInt32 index = allFilesMode ? i : indices[i];
    if (index < Items.Size())
      totalSize += ItemSize(index);
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
    const Int32 askMode = testMode ? NExtract::NAskMode::kTest : NExtract::NAskMode::kExtract;
    CMyComPtr<ISequentialOutStream> outStream;
    RINOK(extractCallback->GetStream(index, &outStream, askMode))
    size = index < Items.Size() ? ItemSize(index) : 0;
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

}}
