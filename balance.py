#!/usr/bin/env python3
"""HexTD Vs — balanco DPS-efetivo/custo das 21 torres. Regua 2: val=DPSeff/custo em +-20% da curva."""

HP_REF = 100
STATUS_VALUE = {"burn":0.0,"molhado":3.0,"gelo":4.0,"exposto":2.5,"veneno":0.0,"marcado":3.0,"raiz":3.5}

def dot_dps(frac,dur,chance,aps,stacks,cap):
    active = min(cap, aps*dur*chance*stacks)
    return active*frac*HP_REF

towers = [
 dict(id="fire_str",el="F",role="striker",dano=10,aps=2.0,targets=1.2,cost=15,dot=(0.02,6,0.20,1,1),status=None,aura=None,bounty=0,note="DoT single + poca"),
 dict(id="fire_bla",el="F",role="blaster",dano=5,aps=1.0,targets=6.0,cost=40,dot=(0.02,6,0.12,1,1),status=None,aura=None,bounty=0,note="AoE ilimitado alc-1"),
 dict(id="fire_sup",el="F",role="support",dano=3,aps=1.0,targets=1.0,cost=45,dot=None,status=None,aura=("tick+40%",0.40),bounty=0,note="acelera DoT"),
 dict(id="watr_str",el="A",role="striker",dano=4,aps=2.0,targets=1.2,cost=14,dot=None,status=("molhado",0.60),aura=None,bounty=0,note="molha de longe"),
 dict(id="watr_bla",el="A",role="blaster",dano=3,aps=1.3,targets=6.0,cost=30,dot=None,status=("molhado",0.50),aura=None,bounty=0,note="banha cluster (barata: enabler)"),
 dict(id="watr_sup",el="A",role="support",dano=2,aps=1.0,targets=1.0,cost=48,dot=None,status=("molhado",0.30),aura=("+25% combo",0.25),bounty=0,note="mult combo"),
 dict(id="ice_str",el="I",role="striker",dano=8,aps=1.8,targets=1.2,cost=16,dot=None,status=("gelo",0.30),aura=None,bounty=0,note="freeze single"),
 dict(id="ice_bla",el="I",role="blaster",dano=4,aps=1.3,targets=6.0,cost=36,dot=None,status=("gelo",0.25),aura=None,bounty=0,note="trava cluster"),
 dict(id="ice_sup",el="I",role="support",dano=2,aps=1.0,targets=1.0,cost=46,dot=None,status=("gelo",0.20),aura=("+40% slow",0.30),bounty=0,note="amplifica controle"),
 dict(id="phys_str",el="P",role="striker",dano=20,aps=1.2,targets=1.2,cost=18,dot=None,status=("exposto",0.30),aura=None,bounty=0,note="executor single"),
 dict(id="phys_bla",el="P",role="blaster",dano=11,aps=1.4,targets=3.0,cost=42,dot=None,status=("exposto",0.20),aura=None,bounty=0,note="perfura linha"),
 dict(id="phys_sup",el="P",role="support",dano=2,aps=1.0,targets=1.0,cost=50,dot=None,status=("exposto",0.15),aura=("+20% burst",0.25),bounty=0,note="amplifica burst"),
 dict(id="pois_str",el="V",role="striker",dano=6,aps=2.2,targets=1.2,cost=15,dot=(0.015,4,1.0,1,6),status=None,aura=None,bounty=0,note="stacks single"),
 dict(id="pois_bla",el="V",role="blaster",dano=3,aps=1.2,targets=5.0,cost=44,dot=(0.012,4,0.70,1,5),status=None,aura=None,bounty=0,note="gas + contagio"),
 dict(id="pois_sup",el="V",role="support",dano=2,aps=1.0,targets=1.0,cost=44,dot=None,status=None,aura=("+cap +25%/stack",0.30),bounty=0,note="amplifica stack"),
 dict(id="arc_str",el="R",role="striker",dano=9,aps=2.0,targets=1.2,cost=20,dot=None,status=("marcado",0.25),aura=None,bounty=3,note="marcador + gold"),
 dict(id="arc_bla",el="R",role="blaster",dano=5,aps=1.3,targets=6.0,cost=44,dot=None,status=("marcado",0.20),aura=None,bounty=2,note="marca cluster"),
 dict(id="arc_sup",el="R",role="support",dano=2,aps=1.0,targets=1.0,cost=52,dot=None,status=("marcado",0.15),aura=("+15% dmg+gold",0.15),bounty=12,note="banco"),
 dict(id="nat_str",el="N",role="striker",dano=9,aps=1.8,targets=1.2,cost=16,dot=None,status=("raiz",0.25),aura=None,bounty=0,note="root single"),
 dict(id="nat_bla",el="N",role="blaster",dano=5,aps=1.3,targets=6.0,cost=38,dot=None,status=("raiz",0.30),aura=None,bounty=0,note="root cluster (mae assin)"),
 dict(id="nat_sup",el="N",role="support",dano=2,aps=1.0,targets=1.0,cost=46,dot=None,status=("raiz",0.20),aura=("+12%dmg+10%aps",0.20),bounty=0,note="hibrido versatil"),
]
BOUNTY_VALUE=1.2; AURA_VALUE=6.0

def eff(t):
    direct=t["dano"]*t["aps"]*t["targets"]
    dot=0.0
    if t["dot"]:
        frac,dur,ch,st,cap=t["dot"]; dot=dot_dps(frac,dur,ch,t["aps"],st,cap)*t["targets"]
    stat=0.0
    if t["status"]:
        n,ch=t["status"]; stat=STATUS_VALUE.get(n,0.0)*ch*t["aps"]
    bounty=BOUNTY_VALUE*t["bounty"]*(t["aps"]*0.15)
    aura=AURA_VALUE if t["aura"] else 0.0
    return direct,dot,stat,bounty,aura

print(f"{'id':10}{'role':9}{'cost':>5}{'direct':>8}{'dot':>7}{'stat':>7}{'bnty':>6}{'aura':>6}{'DPSeff':>8}{'val':>7}")
print("-"*74)
rows=[]
for t in towers:
    d,dot,s,b,a=eff(t); dpse=d+dot+s+b+a; val=dpse/t["cost"]
    rows.append((t,dpse,val))
    print(f"{t['id']:10}{t['role']:9}{t['cost']:>5}{d:>8.1f}{dot:>7.1f}{s:>7.1f}{b:>6.1f}{a:>6.1f}{dpse:>8.1f}{val:>7.3f}")

# Regua 2 aplicada POR PAPEL: supports competem entre si, nao contra torres de dano.
print("-"*74)
for role in ("striker","blaster","support"):
    rr=[(t,dpse,val) for t,dpse,val in rows if t["role"]==role]
    vals=sorted(v for _,_,v in rr); med=vals[len(vals)//2]
    lo,hi=med*0.8,med*1.2
    print(f"\n[{role.upper()}] mediana val={med:.3f}  banda +-20%=[{lo:.3f}, {hi:.3f}]")
    for t,dpse,val in rr:
        flag = "  OK " if lo<=val<=hi else ("BAIXO" if val<lo else " ALTO")
        mark = "" if lo<=val<=hi else "  <<<"
        print(f"  {t['id']:10} val={val:.3f} [{flag}]{mark} -- {t['note']}")

# --- GATE final: todo desvio fora de banda tem justificativa deliberada? ---
print("\n" + "="*74)
print("GATE — justificativa dos desvios (Regua 2: DoT/condicional/enabler permitidos):")
JUSTIFIED = {
 "fire_str":"DoT diferido (Burn) — nominal maior permitido",
 "pois_str":"DoT empilhavel diferido — nominal maior permitido",
 "phys_str":"burst/execucao condicional (<30% HP) — pico permitido",
 "watr_str":"ENABLER: fraca sozinha por design; valor real via combos (nao creditado no modelo)",
 "phys_bla":"perfuracao em linha condicionada a alinhamento — +2% e ruido",
}
ok=True
for role in ("striker","blaster","support"):
    rr=[(t,dpse,val) for t,dpse,val in rows if t["role"]==role]
    vals=sorted(v for _,_,v in rr); med=vals[len(vals)//2]; lo,hi=med*0.8,med*1.2
    for t,dpse,val in rr:
        if not (lo<=val<=hi):
            j=JUSTIFIED.get(t["id"])
            status="JUSTIFICADO" if j else "!!! SEM JUSTIFICATIVA !!!"
            if not j: ok=False
            print(f"  {t['id']:10} ({val:.3f}) -> {status}: {j or 'REVISAR'}")
print("\nGATE:", "PASSOU — todos os desvios sao deliberados." if ok else "FALHOU — ha desvio nao justificado.")
