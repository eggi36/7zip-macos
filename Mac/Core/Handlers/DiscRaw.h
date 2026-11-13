// DiscRaw.h -- what the bridge needs from DiscRaw.cpp.

#ifndef SZ_DISC_RAW_H
#define SZ_DISC_RAW_H

#include "../../../CPP/7zip/IStream.h"

// An Xbox / Xbox 360 disc (an XISO, or a whole disc whose game partition follows a DVD-video
// partition): open it with the "XDVDFS" format, or the ISO / UDF handlers show only the video
// partition (and the handler, which has no signature, is not tried for other extensions).
// The stream is left at 0.
bool SZIsXboxDiscImage(IInStream *stream);

#endif
