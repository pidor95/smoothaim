"""Downloads the Sketchfab source models (glTF) used by
tools/blender/build_sketchfab_kit.py into tools/model_sources/<name>/.

Run:  SKETCHFAB_TOKEN=<api token> python3 tools/fetch_sketchfab.py [name ...]
(the token is the user's own; it is not stored in the repository)
"""
import io
import sys
import json
import os
import urllib.request
import zipfile

MODELS = {
    "ak74m": "84bb0a58a18047069706047639b82899",  # AK-74M by SeveN, CC-BY-4.0
    "rgd5": "886637c9482b4cc4960d0112684baac6",  # Grenade RGD-5 by _Alexandr, CC-BY-4.0
    "fpv": "87f5bbb5b08641b782bc084ddd4082a7",  # FPV kamikaze drone Low-poly by Kvasovich, CC-BY-4.0
    "svd": "7e5c38ec11b54b08b14e49843ad04ed5",  # SVD "Dragunov" by Sergei3D, CC-BY-4.0
    "kobra": "b95a9a049fdc4df1b9f02fb8c7a608e8",  # Low-Poly EKP-1S-03 Kobra Red Dot Sight by Mivoriss57, CC-BY-4.0
    "mavic": "3e5b8566dbe24f4ba65473179650abd1",  # DJI Mavic 2 Pro by mattmaksymowicz, CC-BY-4.0
    "f1": "4ed44b77a00d4116928b15e8b30a5785",  # Low-Poly F-1 Grenade by notcplkerry, CC-BY-4.0
    "pbs1": "cb95b1e5f55842beb9a80587c6ff3f19",  # PBS-1 Silencer for AK-74 5.45x39 by 3dYaroslav, CC-BY-4.0
}
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "model_sources")


def main():
    token = os.environ["SKETCHFAB_TOKEN"]
    for name, uid in MODELS.items():
        if len(sys.argv) > 1 and name not in sys.argv[1:]:
            continue
        req = urllib.request.Request("https://api.sketchfab.com/v3/models/%s/download" % uid,
                                     headers={"Authorization": "Token " + token})
        url = json.load(urllib.request.urlopen(req))["gltf"]["url"]
        data = urllib.request.urlopen(url).read()
        dest = os.path.join(OUT, name)
        os.makedirs(dest, exist_ok=True)
        zipfile.ZipFile(io.BytesIO(data)).extractall(dest)
        print("fetched", name, len(data))


main()
