# ☀️ Voltage Rise Mitigation Strategies for Solar PV Integration in LV Distribution Networks

## Overview

A **MATLAB simulation** of a comparative study of **six voltage rise mitigation strategies** for high-penetration rooftop solar PV integration in a low-voltage (LV) residential distribution network, implemented on the **IEEE European LV Test Feeder**. The study evaluates active power strategies, reactive power strategies, and proposes a novel **Adaptive Droop control law** — all benchmarked against the EN 50160 statutory voltage limit of 1.05 pu.

> 📄 **Results written up in IEEE conference paper format**
> Course Project | Transactive Energy Markets | NIT Warangal | 2026

---

## 🛠️ Tools & Environment

| Tool | Version | Purpose |
|------|---------|---------|
| MATLAB | R2025a | Forward-sweep load flow, strategy simulation, plotting |
| IEEE European LV Test Feeder | 2015 | Standard benchmark distribution network |

---

## 🏗️ System Architecture

| Component | Description |
|-----------|-------------|
| **Test Feeder** | IEEE European LV Test Feeder — 19-bus, 400 V, 200 kVA radial network |
| **Cable Type** | 95 mm² XLPE underground, 100 m segments; R/X = 3.1 |
| **Load Model** | 19 residential households; P_load = 1.50 kW/bus, PF = 0.95 |
| **PV Model** | Rooftop PV at every bus; P_pv@100% = 7.76 kWp/bus |
| **EESS Model** | Home battery at every bus; P_batt_max = 1.94 kW (25% of PV nameplate) |
| **Inverter Model** | IEEE 1547-2018 compliant; Q_max = 3.60 kVAR per inverter |
| **Load Flow** | Forward-sweep algorithm; convergence < 1e-8 pu; max 5000 iterations |
| **Voltage Limit** | V_max = 1.05 pu per EN 50160 standard |

---

## 📁 Project Structure

```
PV-Voltage-Rise-Mitigation-LV-Networks/
│
├── MATLAB/                        # Simulation scripts
│   └── TEM_Course_Project_V6.m    # Main simulation file — all 6 strategies
├── Results/                       # Simulation output plots
│   ├── voltage_profile_all_strategies.png
│   ├── hosting_capacity_bar_chart.png
│   ├── curtailment_vs_eess_energy.png
│   ├── reactive_power_usage.png
│   ├── voltage_violations.png
│   └── adaptive_droop_gain_curve.png
└── References/                    # Key references
    └── Yang_et_al_2015_PVNET.pdf
```

---

## ▶️ How to Run

1. Open **MATLAB R2025a** (or compatible version)
2. Navigate to the `MATLAB/` folder
3. Open and run `TEM_Course_Project_V6.m`
4. MATLAB will simulate all 6 strategies and generate 11 figures automatically
5. Full results summary prints to console on completion

> ⚠️ No additional toolboxes required — pure MATLAB simulation using built-in functions only.

---

## 📊 Simulation Results

### Hosting Capacity by Strategy
| No. | Strategy | Hosting Capacity | Improvement over Baseline |
|-----|----------|-----------------|--------------------------|
| 1 | No Mitigation (Baseline) | 20% | — |
| 2 | Active Power Curtailment | 60% | +200% ✅ |
| 3 | Distributed EESS (Home Battery) | 60% | +200% ✅ |
| 4 | Static Q Control (PF = 0.95) | 30% | +50% |
| 5 | Voltage-Droop Q Control (Fixed Kq) | 40% | +100% |
| **6** | **Adaptive Droop Q (Proposed)** | **50%** | **+150% ✅ Best reactive** |

- ✅ Active strategies triple hosting capacity from 20% to 60% (3× improvement)
- ✅ Proposed adaptive droop achieves 50% — 25% better than fixed droop
- ✅ Zero hardware cost for adaptive droop — inverter firmware update only
- ⚠️ Reactive-only strategies insufficient beyond 50% on high R/X feeders

---

### Terminal Bus 19 Voltage (pu) — Critical Monitoring Point
| Strategy | 40% Penetration | 50% Penetration | 60% Penetration |
|----------|----------------|----------------|----------------|
| No Mitigation | 1.0697 pu ❌ | 1.0892 pu ❌ | 1.1084 pu ❌ |
| Active Curtailment | 1.0500 pu ✅ | 1.0500 pu ✅ | 1.0500 pu ✅ |
| Distributed EESS | 1.0500 pu ✅ | 1.0500 pu ✅ | 1.0500 pu ✅ |
| Static Q (PF=0.95) | 1.0542 pu ❌ | 1.0720 pu ❌ | 1.0905 pu ❌ |
| Droop Q (Fixed Kq) | 1.0378 pu ✅ | 1.0566 pu ❌ | 1.0740 pu ❌ |
| **Adaptive Droop Q** | **1.0346 pu ✅** | **1.0523 pu ❌** | **1.0690 pu ❌** |

> Voltage limit: V_max = 1.05 pu (EN 50160). Bus 19 is always the critical bus due to cumulative reverse injection along the 19-bus radial feeder.

---

### Novel Contribution — Adaptive Droop Control Law
| Parameter | Value |
|-----------|-------|
| Proposed Law | K_q_adapt = Kq × (1 + α × L_PV) |
| Scaling Factor α | 2.0 (tuned) |
| Gain at 0% penetration | 0.50 kVAR/pu (identical to fixed droop) |
| Gain at 60% penetration | 1.10 kVAR/pu (2.2× stronger) |
| Hosting Capacity | 50% vs 40% (fixed droop) — **25% improvement** |
| Peak Voltage Reduction | 1.069 pu vs 1.074 pu at 60% — **5 mpu better** |
| Hardware Cost | Zero — inverter firmware reprogramming only |
| Implementation | Gain updated from DMS or estimated from inverter active power output |

- ✅ Penetration-aware behaviour — activates proportionally only when needed
- ✅ Identical to fixed droop at low penetration (no unnecessary reactive absorption)
- ✅ Substantially stronger at high penetration where voltage support is critical
- ✅ Q_max enforced at all penetration levels per IEEE 1547-2018

---

### EESS vs Curtailment — Energy Analysis
| Metric | Active Curtailment | Distributed EESS |
|--------|-------------------|-----------------|
| Voltage Control | Identical (both hold V = 1.050 pu) | Identical |
| Energy Outcome | ❌ Wasted permanently | ✅ Stored for evening dispatch |
| Power at 60% penetration | 29.5 kW discarded | 29.5 kW stored |
| Energy over 4h peak period | ~118 kWh lost | ~118 kWh saved |
| Battery usage at 60% pen | — | 85% of P_batt_max ✅ (within limits) |
| Battery usage at 40% pen | — | 5% of P_batt_max ✅ |

- ✅ Voltage control is physically identical — energy destination is completely opposite
- ✅ EESS sizing validated: 1.94 kW / 9.7 kWh battery adequate at all penetration levels
- ⚠️ Curtailment is simpler but wastes solar investment — EESS preferred for high penetration

---

### Simulation Parameters
| Parameter | Value | Source |
|-----------|-------|--------|
| n_bus | 19 | IEEE European LV Feeder |
| V_base | 400 V | IEC standard |
| S_base | 200 kVA | IEEE European LV Feeder |
| R per segment | 0.040 pu | 95 mm² XLPE |
| X per segment | 0.013 pu | 95 mm² XLPE |
| R/X ratio | 3.1 | Calculated |
| P_load per bus | 1.50 kW | Typical residential |
| P_pv at 100% | 7.76 kWp | Yang et al. 2015 |
| V_max | 1.05 pu | EN 50160 |
| V_ref | 1.00 pu | Nominal |
| P_batt_max | 1.94 kW | 25% of PV nameplate |
| PF_static | 0.95 lag | Yang et al. 2015 |
| Kq fixed droop | 0.5 kVAR/pu | Tuned |
| Q_max inverter | 3.60 kVAR | IEEE 1547-2018 |
| α adaptive droop | 2.0 | Proposed |

---

## 🔑 Key Concepts Demonstrated

- Forward-sweep load flow for radial LV distribution networks
- Voltage rise mechanism in high R/X feeders — active power dominates voltage (3× vs reactive)
- Active power curtailment — voltage control with permanent energy loss
- Distributed EESS (home batteries) — voltage control with energy storage for evening dispatch
- Static reactive power control — fixed PF = 0.95 lagging inverter operation
- Voltage-droop Q(U) control — communication-free local reactive power regulation
- Novel adaptive droop control — penetration-aware gain scaling with zero hardware cost
- Hosting capacity analysis — maximum PV penetration within statutory voltage limits
- IEEE 1547-2018 compliant inverter reactive power modeling
- EN 50160 voltage quality standard compliance assessment

---

## 📄 Paper

Results are written up in **IEEE conference paper format**:

> *"Comparative Analysis of Voltage Rise Mitigation Strategies for High-Penetration Solar PV Integration in Low-Voltage Distribution Networks"*
> IEEE European LV Test Feeder | NIT Warangal | 2026

The paper presents four specific contributions:
1. Unified forward-sweep load-flow simulation of six strategies under identical grid conditions
2. Quantification of energy stored vs. wasted trade-off between EESS and curtailment
3. Proposal and evaluation of the adaptive droop law K_q_adapt = Kq(1 + α·L_PV)
4. Consolidated hosting-capacity and violation-analysis decision framework for DSOs

---

## 📚 Key References

1. G. Yang et al., "Voltage rise mitigation for solar PV integration at LV grids: Studies from PVNET.dk," *J. Mod. Power Syst. Clean Energy*, vol. 3, no. 3, pp. 411–421, 2015.
2. IEEE Std 1547-2018: Standard for Interconnection and Interoperability of Distributed Energy Resources.
3. EN 50160: Voltage Characteristics of Electricity Supplied by Public Distribution Systems, CENELEC, 2010.
4. IEEE Power & Energy Society, "IEEE European Low Voltage Test Feeder," IEEE PES Distribution Test Feeders, 2015.

---

## 👤 Author

**Sanmith G S**

- 🎓 M.Tech – Smart Electric Grid, **NIT Warangal**
- 🎓 B.E – Electrical & Electronics Engineering, **BMS College of Engineering, Bengaluru**
- 🔗 [LinkedIn](https://www.linkedin.com/in/sanmith-g-s)
- 🐙 [GitHub](https://github.com/SanmithGS)
- 📧 sannysanmith@gmail.com
