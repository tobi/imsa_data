// Track layout images - static imports for Observable Framework
// FileAttachment requires static string literals, so we enumerate all images here

import {FileAttachment} from "npm:@observablehq/stdlib";

// Static FileAttachment references for all track images
const trackImages = {
  "bahrain": FileAttachment("../assets/tracks/bahrain.png"),
  "barber": FileAttachment("../assets/tracks/barber.png"),
  "barcelona-catalunya": FileAttachment("../assets/tracks/barcelona-catalunya.png"),
  "belle-isle": FileAttachment("../assets/tracks/belle-isle.png"),
  "carolina-motorsports-park": FileAttachment("../assets/tracks/carolina-motorsports-park.png"),
  "charlotte": FileAttachment("../assets/tracks/charlotte.png"),
  "circuit-of-the-americas": FileAttachment("../assets/tracks/circuit-of-the-americas.png"),
  "daytona": FileAttachment("../assets/tracks/daytona.png"),
  "detroit": FileAttachment("../assets/tracks/detroit.png"),
  "fuji": FileAttachment("../assets/tracks/fuji.png"),
  "imola": FileAttachment("../assets/tracks/imola.png"),
  "indianapolis": FileAttachment("../assets/tracks/indianapolis.png"),
  "jerez": FileAttachment("../assets/tracks/jerez.png"),
  "laguna-seca": FileAttachment("../assets/tracks/laguna-seca.png"),
  "le-mans": FileAttachment("../assets/tracks/le-mans.png"),
  "lime-rock": FileAttachment("../assets/tracks/lime-rock.png"),
  "long-beach": FileAttachment("../assets/tracks/long-beach.png"),
  "losail": FileAttachment("../assets/tracks/losail.png"),
  "martinsville": FileAttachment("../assets/tracks/martinsville.png"),
  "miami": FileAttachment("../assets/tracks/miami.png"),
  "mid-ohio": FileAttachment("../assets/tracks/mid-ohio.png"),
  "misano": FileAttachment("../assets/tracks/misano.png"),
  "montreal": FileAttachment("../assets/tracks/montreal.png"),
  "mont-tremblant": FileAttachment("../assets/tracks/mont-tremblant.png"),
  "monza": FileAttachment("../assets/tracks/monza.png"),
  "mosport": FileAttachment("../assets/tracks/mosport.png"),
  "motorland-aragon": FileAttachment("../assets/tracks/motorland-aragon.png"),
  "mugello": FileAttachment("../assets/tracks/mugello.png"),
  "nola": FileAttachment("../assets/tracks/nola.png"),
  "nurburgring": FileAttachment("../assets/tracks/nurburgring.png"),
  "paul-ricard": FileAttachment("../assets/tracks/paul-ricard.png"),
  "portimao": FileAttachment("../assets/tracks/portimao.png"),
  "red-bull-ring": FileAttachment("../assets/tracks/red-bull-ring.png"),
  "road-america": FileAttachment("../assets/tracks/road-america.png"),
  "road-atlanta": FileAttachment("../assets/tracks/road-atlanta.png"),
  "sao-paulo": FileAttachment("../assets/tracks/sao-paulo.png"),
  "sebring": FileAttachment("../assets/tracks/sebring.png"),
  "silverstone": FileAttachment("../assets/tracks/silverstone.png"),
  "sonoma": FileAttachment("../assets/tracks/sonoma.png"),
  "spa-francorchamps": FileAttachment("../assets/tracks/spa-francorchamps.png"),
  "st-petersburg": FileAttachment("../assets/tracks/st-petersburg.png"),
  "the-firm": FileAttachment("../assets/tracks/the-firm.png"),
  "toronto": FileAttachment("../assets/tracks/toronto.png"),
  "trois-rivieres": FileAttachment("../assets/tracks/trois-rivieres.png"),
  "vallelunga": FileAttachment("../assets/tracks/vallelunga.png"),
  "virginia-international-raceway": FileAttachment("../assets/tracks/virginia-international-raceway.png"),
  "watkins-glen": FileAttachment("../assets/tracks/watkins-glen.png")
};

// Get image URL for a track (returns null if no image available)
export async function getTrackImageUrl(trackId) {
  const file = trackImages[trackId];
  if (file) {
    try {
      return await file.url();
    } catch (e) {
      return null;
    }
  }
  return null;
}

// Export the map for bulk access
export {trackImages};
