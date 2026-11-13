// CompressedImages.h -- a block-compressed image as one stream (CSO, ZSO, CISO, ISZ, zisofs,
// ECM, CHD): the format decodes one block at a time, this base caches it and serves reads.

#ifndef SZ_COMPRESSED_IMAGES_H
#define SZ_COMPRESSED_IMAGES_H

#include "../../../CPP/Common/MyBuffer.h"
#include "../../../CPP/7zip/Archive/HandlerCont.h"

namespace NArchive {
namespace NBlockImage {

HRESULT Inflate(const Byte *in, size_t inSize, Byte *out, size_t outSize, bool zlib, size_t &produced);
HRESULT Bunzip2(const Byte *in, size_t inSize, Byte *out, size_t outSize, size_t &produced);
bool Lz4Block(const Byte *in, size_t inSize, Byte *out, size_t outSize, size_t &produced);

class CBlockHandler: public CHandlerImg
{
protected:
  UInt32 _blockSize;
  UInt64 _phySize;
  const char *_method;
  bool _isArc;
  bool _unsupported;

  // The decoded block `block` into `out` (_blockSize bytes); S_FALSE for a data error.
  virtual HRESULT DecodeBlock(UInt64 block, Byte *out) = 0;
  virtual void CloseFormat() {}
  HRESULT ReadAt(UInt64 offset, Byte *data, size_t size);

public:
  Z7_IFACE_COM7_IMP(IInArchive_Img)
  Z7_IFACE_COM7_IMP(IInArchiveGetStream)
  Z7_IFACE_COM7_IMP(ISequentialInStream)

  CBlockHandler(): _blockSize(2048), _phySize(0), _method(NULL), _isArc(false), _unsupported(false),
      _cachedBlock((UInt64)(Int64)-1) {}

private:
  CByteBuffer _cache;
  UInt64 _cachedBlock;
};

}}

#endif
