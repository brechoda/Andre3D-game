"""Corrige o osso Root nas animações BIKEd_* do andre_armed_biked.glb.

Problema: BIKEd_jumponL/jumponR/getoff*/kick/hit/pushes/driveby* vinham com a
rotação do Root igual à pose de descanso do esqueleto (~90° em Y), enquanto
BIKEd_Ride, IDLE_stance etc. usam outra (~91° diferente). Resultado: ao subir na
moto o corpo inteiro fica girado 91° e "estala" quando a animação termina.

Solução: copia a rotação do Root de BIKEd_Ride para todas as BIKEd_* em que o
Root é constante e diferente. Edição in-place no buffer (mesmo tamanho).

Uso: python3 tools/fix_bike_root_rotation.py [caminho.glb]
"""
import json, struct, sys
import numpy as np

path = sys.argv[1] if len(sys.argv) > 1 else "assets/models/andre_armed_biked.glb"
data = bytearray(open(path, "rb").read())
jl = struct.unpack("<I", data[12:16])[0]
j = json.loads(bytes(data[20:20 + jl]))
bin_start = 20 + jl + 8
nodes = j["nodes"]

def acc_off(i):
    a = j["accessors"][i]; bv = j["bufferViews"][a["bufferView"]]
    return bin_start + bv.get("byteOffset", 0) + a.get("byteOffset", 0), a["count"]

def root_rot_sampler(anim):
    for ch in anim["channels"]:
        if nodes[ch["target"]["node"]]["name"].strip() == "Root" and ch["target"]["path"] == "rotation":
            return anim["samplers"][ch["sampler"]]
    return None

anims = {a["name"]: a for a in j["animations"]}
off, cnt = acc_off(root_rot_sampler(anims["BIKEd_Ride"])["output"])
ref = np.frombuffer(bytes(data[off:off + 16]), dtype="<f4").copy()
print("Root de referência (BIKEd_Ride):", ref.round(4))

patched = []
for name, anim in anims.items():
    if not name.startswith("BIKEd_") or name == "BIKEd_Ride":
        continue
    s = root_rot_sampler(anim)
    if s is None:
        continue
    o, c = acc_off(s["output"])
    q = np.frombuffer(bytes(data[o:o + 16 * c]), dtype="<f4").reshape(c, 4)
    if c != 2 or not np.allclose(q[0], q[1], atol=1e-4):
        continue  # Root animado de verdade: não mexe
    if abs(float(np.dot(q[0], ref))) > 0.999:
        continue  # já está certo
    for k in range(c):
        data[o + 16 * k:o + 16 * k + 16] = ref.tobytes()
    patched.append(name)

open(path, "wb").write(bytes(data))
print("Corrigidas:", ", ".join(patched) or "nenhuma")
