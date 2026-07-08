import Foundation

enum HybridMapStyle {
  /// Online satellite + label overlay (matches Android `buildOnlineEsriHybridStyleJson`).
  private static let onlineEsriStyleJSON = """
  {
    "version": 8,
    "sources": {
      "esri-satellite": {
        "type": "raster",
        "tiles": [
          "https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}"
        ],
        "tileSize": 256,
        "maxzoom": 18,
        "attribution": "Esri, Maxar, Earthstar Geographics"
      },
      "osm-labels": {
        "type": "raster",
        "tiles": [
          "https://tiles.openstreetmap.org/{z}/{x}/{y}.png"
        ],
        "tileSize": 256,
        "maxzoom": 18,
        "attribution": "OpenStreetMap contributors"
      }
    },
    "layers": [
      {
        "id": "esri-satellite-layer",
        "type": "raster",
        "source": "esri-satellite"
      },
      {
        "id": "osm-labels-layer",
        "type": "raster",
        "source": "osm-labels",
        "paint": {
          "raster-opacity": 0.4
        }
      }
    ]
  }
  """

  /// Load hybrid style via local file URL — more stable than `styleJSON` when switching styles.
  static func onlineEsriStyleFileURL() -> URL? {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("ubutare-hybrid-esri-style.json")
    do {
      try onlineEsriStyleJSON.write(to: url, atomically: true, encoding: .utf8)
      return url
    } catch {
      return nil
    }
  }
}
