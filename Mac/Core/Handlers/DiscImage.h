// DiscImage.h -- the shared part of the optical-disc image handlers (a macOS addition, modelled
// on TC4Shell's Iso7z plugin for 7-Zip): a disc as a list of tracks, each shown as a file --
// a data track as "TrackNN.iso" (the 2048-byte user data of its sectors, which 7-Zip opens as
// ISO 9660 / UDF in turn), an audio track as "TrackNN.wav" (its 2352-byte frames behind a WAV
// header), a data track whose sectors cannot be read as user data as "TrackNN.bin" (raw).
//
// A format handler (CUE/BIN, CCD/IMG, GDI, MDS/MDF, NRG, CDI, CHD) only fills `Tracks` and
// `Sources`; this base serves the items, their streams and their extraction.

#ifndef SZ_DISC_IMAGE_H
#define SZ_DISC_IMAGE_H

#include "../../../CPP/Common/MyCom.h"
#include "../../../CPP/Common/MyString.h"
#include "../../../CPP/Common/MyVector.h"
#include "../../../CPP/7zip/Archive/IArchive.h"

namespace NArchive {
namespace NDiscImage {

const UInt32 kCookedSize = 2048;   // Mode 1 / Mode 2 Form 1 user data
const UInt32 kRawSize = 2352;      // a whole CD frame: sync, header, data, EDC/ECC (or audio)
const UInt32 kMode2Size = 2336;    // Mode 2 without sync and header
const UInt32 kSubSize = 96;        // P-W subchannel after a raw sector
const UInt32 kWavHeaderSize = 44;

struct CTrack
{
  UInt32 Number;
  UInt32 Session;
  bool Audio;
  bool AudioKnown;       // the descriptor says audio / data; otherwise detected from the sync
  unsigned SourceIndex;  // into CDiscHandler::Sources
  UInt64 Offset;         // byte offset of the first sector in that source
  UInt64 NumSectors;
  UInt32 SectorSize;     // main data per sector in the source: 2048, 2336, 2352
  UInt32 Stride;         // from one sector to the next in the source (sector + subchannel)
  // Filled in by CDiscHandler::FinishTracks:
  UInt32 UserOffset;     // where the exposed bytes start inside a sector
  UInt32 UserSize;       // exposed bytes per sector
  bool RawData;          // a data track exposed as raw sectors (.bin)
  bool SwapAudio;        // audio stored big-endian (CHD): swapped to the WAV's little-endian
  AString Name;          // a fixed item name (a hard-disk CHD's "image.img"), else TrackNN.ext
  UInt64 Lba;            // the disc address of the first sector (where a file system points)
  bool LbaKnown;         // given by the descriptor; otherwise laid out from the sessions

  CTrack():
      Number(0), Session(1), Audio(false), AudioKnown(false), SourceIndex(0), Offset(0),
      NumSectors(0), SectorSize(kRawSize), Stride(kRawSize),
      UserOffset(0), UserSize(kRawSize), RawData(false), SwapAudio(false), Lba(0), LbaKnown(false) {}

  UInt64 ExposedSize() const { return NumSectors * UserSize + (Audio ? kWavHeaderSize : 0); }
  UInt64 PackedSize() const { return NumSectors * Stride; }
};

// A file of a Mode 2 (CD-ROM XA) file system that holds Form 2 sectors (a Video CD's .DAT, a
// PlayStation .STR): shown as Windows shows it, a RIFF "CDXA" file of its raw 2352-byte sectors.
// The file system's other files come with it as plain files, so the folder is complete.
struct CXaFile
{
  AString Path;
  UInt32 Lba;
  UInt32 Length;         // the directory's data length
  bool Raw;              // RIFF CDXA of raw sectors
  Byte Record[14];       // the directory record's XA system-use field (RIFF "fmt " data)

  UInt32 NumSectors() const { return (Length + kCookedSize - 1) / kCookedSize; }
  UInt64 Size() const { return Raw ? kWavHeaderSize + (UInt64)NumSectors() * kRawSize : Length; }
};

// One ISO per session of a multi-session disc: the disc from LBA 0 to the session's end, so the
// session's file system (which also points into earlier sessions) reads as on the disc.
struct CSessionIso
{
  UInt32 Session;
  UInt64 NumSectors;
};

struct CItem
{
  Byte Kind;             // 0 track, 1 session, 2 XA file
  unsigned Index;
};

class CDiscHandler:
  public IInArchive,
  public IInArchiveGetStream,
  public CMyUnknownImp
{
  Z7_COM_UNKNOWN_IMP_2(IInArchive, IInArchiveGetStream)
  Z7_IFACE_COM7_IMP(IInArchive)
  Z7_IFACE_COM7_IMP(IInArchiveGetStream)

protected:
  CObjectVector< CMyComPtr<IInStream> > Sources;
  CObjectVector<CTrack> Tracks;
  UInt64 PhySize;
  bool IsArc;
  bool Unsupported;
  AString MissingFile;   // a referenced data file that could not be opened
  UStringVector _volumeNames;   // parallel to Sources

  // Reads the descriptor from `stream` (the opened file) and fills Tracks / Sources.
  virtual HRESULT ParseImage(IInStream *stream, IArchiveOpenCallback *callback) = 0;
  virtual const char *FormatName() const = 0;

  // A file next to the opened one (a .bin of a .cue, the .mdf of an .mds): Sources index, or -1.
  HRESULT AddVolume(IArchiveOpenCallback *callback, const UString &name, int &index);
  // The opened file's own name (for "same name, other extension" lookups).
  static UString ArchiveName(IArchiveOpenCallback *callback);

  // Decides each track's exposed layout (Mode 1 / Mode 2 / audio) from its sectors.
  HRESULT FinishTracks();

  // The disc as addressed by its file systems (DiscExtras.cpp).
  CObjectVector<CXaFile> XaFiles;
  CRecordVector<CSessionIso> SessionIsos;
  CRecordVector<CItem> Items;
  void AssignLbas();
  int FindTrack(UInt64 lba) const;
  HRESULT ReadUser(UInt64 lba, Byte *out);     // 2048 bytes; zeros where no data sector is
  HRESULT ReadRaw(UInt64 lba, Byte *out);      // 2352 bytes; S_FALSE where none is stored
  void BuildSessions();
  HRESULT ParseXa();
  void BuildItems();
  UInt64 ItemSize(unsigned index) const;
  friend class CSessionStream;
  friend class CXaStream;
  friend HRESULT CreateExtraStream(CDiscHandler *handler, const CItem &item, ISequentialInStream **stream);

public:
  CDiscHandler(): PhySize(0), IsArc(false), Unsupported(false) {}
  virtual ~CDiscHandler() {}
};

// The parsed "mm:ss:ff" of a cue sheet (75 frames per second); false when malformed.
bool ParseMsf(const AString &s, UInt32 &frames);

// A text descriptor (CUE, GDI, CCD) of at most `maxSize` bytes, or S_FALSE.
HRESULT ReadSmallText(IInStream *stream, size_t maxSize, AString &text);

}}

#endif
