%% ================================================================
%  PV VOLTAGE RISE MITIGATION — IEEE EUROPEAN LV TEST FEEDER
%  Course Project | Based on: Yang et al. (2015), PVNET.dk
%
%  Grid : IEEE European LV Test Feeder
%         19 buses | 400 V | 200 kVA | XLPE cable | R/X = 3.1
%
%  Strategies:
%   1. No Mitigation        — Baseline (do nothing)
%   2. Active Curtailment   — Reduce PV output when V > Vmax
%   3. Distributed EESS     — Home battery at every bus, uniform charging
%   4. Static Q Control     — Fixed PF = 0.95 lagging (from paper)
%   5. Droop Q Control      — Q proportional to voltage rise
%   6. Adaptive Droop Q     — Droop gain scales with penetration level
%
%  Battery Sizing (Physically Realistic):
%    P_load    = 1.50 kW/house
%    Ppv@100%  = 7.76 kW/house
%    Pbatt_max = 1.94 kW/house  (25% of PV nameplate, ~10 kWh battery)
%    Ratio Pbatt/P_load = 1.29x  — standard grid-tied home battery
%
%  All strategies verified by Python simulation before coding.
%  Expected at 60% pen: No Mitigation=1.108 | Curtail=1.050 | EESS=1.050
%                       StaticQ=1.091       | Droop=1.074 | Adapt=1.069
%
%  Run: >> pv_voltage_mitigation
%% ================================================================

clc; clear; close all;

%% ============================================================
%  SECTION 1: GRID PARAMETERS  (all values in per-unit)
%  Sbase = 200 kVA,  Vbase = 400 V,  Zbase = 0.8 ohm
%  Cable: 95mm2 XLPE underground, 100m segments
%    R_seg = 0.032 ohm => 0.032/0.8 = 0.040 pu
%    X_seg = 0.011 ohm => 0.011/0.8 = 0.013 pu
%    R/X = 3.1 (high resistance — active power dominates voltage)
%% ============================================================

n_bus     = 19;
Vtx       = 1.00;        % Transformer LV output (pu)
Sbase_kVA = 200;
R         = 0.040;       % Resistance per 100m segment (pu)
X         = 0.013;       % Reactance per 100m segment (pu)

P_load = 0.0075;         % Active load per bus (pu) = 1.50 kW/house
Q_load = 0.0025;         % Reactive load per bus (pu)

Vmax = 1.05;             % Upper voltage limit (pu) — EN 50160
Vref = 1.00;             % Nominal voltage / droop reference (pu)

%% ============================================================
%  SECTION 2: PV SIZING
%  Ppv_at_100 = 0.03882 pu/bus = 7.76 kWp rooftop panel
%  At 60% pen: Ppv = 0.0233 pu >> P_load = 0.0075 pu
%  Net injection = +0.0158 pu/bus => voltage rises bus by bus
%% ============================================================

pen_levels = 0:10:60;
n_pen      = length(pen_levels);
Ppv_at_100 = 0.03882;
P_pv_max   = pen_levels / 100 * Ppv_at_100;

%% ============================================================
%  SECTION 3: CONTROL PARAMETERS
%% ============================================================

%--- Strategy 3: Distributed EESS ---
%  Pbatt_max = 25% of PV nameplate = 1.94 kW per house
%  Physical justification:
%    - Standard grid-tied home battery recommendation (MNRE, India)
%    - Store 20-30% of daily PV generation for self-consumption
%    - At C/2 charge rate: 1.94 kW => 9.7 kWh battery capacity
%    - 9.7 kWh = ~7 hrs of avg household consumption (1.5 kW)
%    - Ratio Pbatt_max / P_load = 1.29x — realistic (< 1.5x is acceptable)
%  At 60% pen: battery uses 1.65 kW = 85% of Pbatt_max — within limits
Pbatt_max = 0.25 * Ppv_at_100;   % = 0.009705 pu = 1.941 kW/house

%--- Strategies 4, 5, 6: Reactive Power Control ---
pf_static = 0.95;
Q_absorb  = @(P) P * tan(acos(pf_static));   % = 0.329 * P

% Kq: droop gain | Qmax_inv: IEEE 1547-2018 rated Q limit
%   S_inv = Ppv_at_100 / PF = 7.76/0.95 = 8.17 kVA
%   Qmax  = 0.44 * S_inv = 3.60 kVAR
Kq       = 0.5;
S_inv    = Ppv_at_100 / pf_static;
Qmax_inv = 0.44 * S_inv;          % = 0.01798 pu = 3.60 kVAR

% alpha: adaptive droop scaling factor (Strategy 6)
%   Kq_adapt = Kq * (1 + alpha * penetration)
%   At 0%  pen => Kq_adapt = 0.50  (same as fixed droop)
%   At 60% pen => Kq_adapt = 1.10  (2.2x stronger)
alpha = 2.0;

fprintf('============================================\n');
fprintf('  Grid: IEEE European LV Test Feeder\n');
fprintf('  R=%.3f pu | X=%.3f pu | R/X=%.1f\n', R, X, R/X);
fprintf('  P_load    = %.2f kW/house\n', P_load*Sbase_kVA);
fprintf('  Ppv@100%%  = %.2f kW/house\n', Ppv_at_100*Sbase_kVA);
fprintf('  Pbatt_max = %.3f kW/house (25%% of PV)\n', Pbatt_max*Sbase_kVA);
fprintf('  Ratio Pbatt/Pload = %.2fx\n', Pbatt_max/P_load);
fprintf('  Qmax_inv  = %.2f kVAR (IEEE 1547-2018)\n', Qmax_inv*Sbase_kVA);
fprintf('============================================\n\n');

%% ============================================================
%  SECTION 4: SIMULATION — FORWARD SWEEP LOAD FLOW
%  Core equation (Yang et al. 2015, Eq.3):
%    V(k+1) = V(k) + [P_flow*R + Q_flow*X] / V(k)
%  P_flow(k) = sum of net injections from bus k to n_bus
%  Positive net injection = reverse power flow = voltage RISES
%% ============================================================

V_none    = zeros(n_pen, n_bus);
V_curtail = zeros(n_pen, n_bus);
V_eess    = zeros(n_pen, n_bus);
V_static  = zeros(n_pen, n_bus);
V_droop   = zeros(n_pen, n_bus);
V_adapt   = zeros(n_pen, n_bus);

P_curtailed   = zeros(1, n_pen);
P_stored_eess = zeros(1, n_pen);   % Total power stored (pu)
Pb_each_log   = zeros(1, n_pen);   % Per-house charging power (kW)
Q_used_static = zeros(1, n_pen);
Q_used_droop  = zeros(1, n_pen);
Q_used_adapt  = zeros(1, n_pen);

for ip = 1:n_pen
    Ppv         = P_pv_max(ip);
    penetration = pen_levels(ip) / 100;

    %% --- Strategy 1: No Mitigation --------------------------------
    %  Full PV output, no control. Shows worst-case voltage rise.
    %  Voltage rises progressively from Bus 1 to Bus 19 as cumulative
    %  reverse injections stack up along the feeder.
    V = Vtx;
    for k = 1:n_bus
        P_flow = (Ppv - P_load) * (n_bus - k + 1);
        Q_flow = (0   - Q_load) * (n_bus - k + 1);
        V = V + (P_flow*R + Q_flow*X) / V;
        V_none(ip, k) = V;
    end

    %% --- Strategy 2: Active Curtailment ---------------------------
    %  Reduce PV output in steps (0.00002 pu) until max(V) <= Vmax.
    %  Unlike EESS: energy is permanently WASTED (not stored).
    %  Voltage control is identical to EESS — energy outcome is not.
    Ppv_c = Ppv;
    Vp    = V_none(ip,:);
    for iter = 1:2000
        V = Vtx; Vp_new = zeros(1, n_bus);
        for k = 1:n_bus
            P_flow    = (Ppv_c - P_load) * (n_bus - k + 1);
            Q_flow    = (0     - Q_load) * (n_bus - k + 1);
            V         = V + (P_flow*R + Q_flow*X) / V;
            Vp_new(k) = V;
        end
        Vp = Vp_new;
        if max(Vp) <= Vmax + 1e-4; break; end
        Ppv_c = Ppv_c - 0.00002;
        if Ppv_c < 0; Ppv_c = 0; break; end
    end
    V_curtail(ip,:) = Vp;
    P_curtailed(ip) = max((Ppv - Ppv_c) * n_bus, 0);

    %% --- Strategy 3: Distributed EESS (uniform fixed charging) -----
    %  Every house has a home battery (~10 kWh, 1.94 kW charge rate).
    %  All batteries charge uniformly at Pb_each (pu/house).
    %  Pb_each found iteratively: increment by 0.000005 pu until
    %  max(V) <= Vmax. Capped at Pbatt_max.
    %
    %  Net injection per bus = Ppv - P_load - Pb_each
    %  KEY vs Curtailment: surplus energy is STORED, discharged at night.
    %  No energy wasted. Battery discharges to supply evening load.
    %
    %  Charging at 40%: 0.094 kW/house  (5% of battery capacity)
    %  Charging at 50%: 0.871 kW/house  (45% of battery capacity)
    %  Charging at 60%: 1.647 kW/house  (85% of battery capacity)
    Pb_each = 0;
    Ve      = V_none(ip,:);
    for iter = 1:5000
        V = Vtx; Ve_new = zeros(1, n_bus);
        for k = 1:n_bus
            P_flow    = (Ppv - P_load - Pb_each) * (n_bus - k + 1);
            Q_flow    = (0   - Q_load)            * (n_bus - k + 1);
            V         = V + (P_flow*R + Q_flow*X) / V;
            Ve_new(k) = V;
        end
        Ve = Ve_new;
        if max(Ve) <= Vmax + 1e-4; break; end
        Pb_each = Pb_each + 0.000005;
        if Pb_each > Pbatt_max; Pb_each = Pbatt_max; break; end
    end
    V_eess(ip,:)      = Ve;
    P_stored_eess(ip) = Pb_each * n_bus;      % Total stored power (pu)
    Pb_each_log(ip)   = Pb_each * Sbase_kVA;  % kW per house

    %% --- Strategy 4: Static Q (Fixed PF = 0.95) -------------------
    %  Every inverter absorbs Q = 0.329*P at all times regardless of V.
    %  Simple single-pass — no iteration needed.
    %  Wasteful at low penetration (absorbs Q when voltage is fine).
    V     = Vtx;
    Q_inv = -Q_absorb(Ppv);
    for k = 1:n_bus
        P_flow = (Ppv   - P_load) * (n_bus - k + 1);
        Q_flow = (Q_inv - Q_load) * (n_bus - k + 1);
        V = V + (P_flow*R + Q_flow*X) / V;
        V_static(ip, k) = V;
    end
    Q_used_static(ip) = abs(Q_inv) * n_bus;

    %% --- Strategy 5: Droop Q (V-triggered, fixed gain) ------------
    %  Q absorbed only when V > Vref = 1.00 pu.
    %  Proportional: bigger voltage deviation => more Q absorbed.
    %  Iterative convergence needed (Q depends on V depends on Q).
    V = Vtx * ones(1, n_bus+1);
    for iter = 1:50
        V_prev = V;
        V(1)   = Vtx;
        for k = 1:n_bus
            Vbus = V(k+1);
            if Vbus > Vref
                Q_inv = -min(Kq * (Vbus - Vref), Qmax_inv);
            else
                Q_inv = 0;
            end
            P_flow = (Ppv   - P_load) * (n_bus - k + 1);
            Q_flow = (Q_inv - Q_load) * (n_bus - k + 1);
            V(k+1) = V(k) + (P_flow*R + Q_flow*X) / V(k);
        end
        if max(abs(V - V_prev)) < 1e-8; break; end
    end
    V_droop(ip,:) = V(2:end);
    Q_per_bus = zeros(1, n_bus);
    for k = 1:n_bus
        if V(k+1) > Vref
            Q_per_bus(k) = min(Kq * (V(k+1) - Vref), Qmax_inv);
        end
    end
    Q_used_droop(ip) = sum(Q_per_bus);

    %% --- Strategy 6: Adaptive Droop Q (gain scales w/ penetration) -
    %  Kq_adapt = Kq * (1 + alpha * penetration)
    %  Same structure as Droop Q but gain increases automatically.
    %  At 0% pen: Kq_adapt = 0.50 (same as fixed droop)
    %  At 60% pen: Kq_adapt = 1.10 (2.2x stronger response)
    Kq_adapt = Kq * (1 + alpha * penetration);
    V = Vtx * ones(1, n_bus+1);
    for iter = 1:50
        V_prev = V;
        V(1)   = Vtx;
        for k = 1:n_bus
            Vbus = V(k+1);
            if Vbus > Vref
                Q_inv = -min(Kq_adapt * (Vbus - Vref), Qmax_inv);
            else
                Q_inv = 0;
            end
            P_flow = (Ppv   - P_load) * (n_bus - k + 1);
            Q_flow = (Q_inv - Q_load) * (n_bus - k + 1);
            V(k+1) = V(k) + (P_flow*R + Q_flow*X) / V(k);
        end
        if max(abs(V - V_prev)) < 1e-8; break; end
    end
    V_adapt(ip,:) = V(2:end);
    Q_per_bus_a = zeros(1, n_bus);
    for k = 1:n_bus
        if V(k+1) > Vref
            Q_per_bus_a(k) = min(Kq_adapt * (V(k+1) - Vref), Qmax_inv);
        end
    end
    Q_used_adapt(ip) = sum(Q_per_bus_a);

end

%% ============================================================
%  SECTION 5: PLOTS
%% ============================================================

bus_vec = 1:n_bus;
get_max = @(Vm) pen_levels(max([find(sum(Vm>Vmax,2)==0, 1,'last'), 1]));

idx40 = 5;   % pen_levels(5) = 40%
idx50 = 6;   % pen_levels(6) = 50%
idx60 = 7;   % pen_levels(7) = 60%

% Consistent colors for all 6 strategies
c1 = [0.85 0.15 0.15];   % Red     — No Mitigation
c2 = [0.15 0.70 0.20];   % Green   — Active Curtailment
c3 = [0.90 0.55 0.00];   % Orange  — Distributed EESS
c4 = [0.15 0.40 0.85];   % Blue    — Static Q
c5 = [0.70 0.10 0.70];   % Magenta — Droop Q
c6 = [0.10 0.10 0.10];   % Black   — Adaptive Droop Q

%% ---- Figure 1: Max Voltage vs Penetration — all 6 strategies ------
figure('Name','Max Voltage vs Penetration','Position',[80 80 740 520]);
hold on; grid on; box on;
p1 = plot(pen_levels, max(V_none,   [],2),'o-','LineWidth',2.2,'MarkerSize',8,'MarkerFaceColor',c1,'Color',c1);
p2 = plot(pen_levels, max(V_curtail,[],2),'s-','LineWidth',2.2,'MarkerSize',8,'MarkerFaceColor',c2,'Color',c2);
p3 = plot(pen_levels, max(V_eess,   [],2),'p-','LineWidth',2.2,'MarkerSize',9,'MarkerFaceColor',c3,'Color',c3);
p4 = plot(pen_levels, max(V_static, [],2),'^-','LineWidth',2.2,'MarkerSize',8,'MarkerFaceColor',c4,'Color',c4);
p5 = plot(pen_levels, max(V_droop,  [],2),'d-','LineWidth',2.2,'MarkerSize',8,'MarkerFaceColor',c5,'Color',c5);
p6 = plot(pen_levels, max(V_adapt,  [],2),'*-','LineWidth',2.2,'MarkerSize',8,'MarkerFaceColor',c6,'Color',c6);
yline(Vmax,'r--','LineWidth',2,'DisplayName',sprintf('%.2f p.u. Limit',Vmax));
xlabel('PV Penetration (%)','FontSize',12);
ylabel('Maximum Bus Voltage (p.u.)','FontSize',12);
title('Voltage Rise Mitigation — All 6 Strategies','FontSize',13,'FontWeight','bold');
subtitle('IEEE European LV Test Feeder (19-bus, 200 kVA, R/X=3.1)');
legend([p1 p2 p3 p4 p5 p6], ...
    {'No Mitigation','Active Curtailment','Distributed EESS', ...
     'Static Q (PF=0.95)','Droop Q','Adaptive Droop Q'}, ...
    'Location','northwest','FontSize',10);
xticks(pen_levels); ylim([0.99 1.15]); xlim([-2 62]);
set(gca,'FontSize',12);

%% ---- Figure 2: Voltage Profile — 40% Penetration ------------------
figure('Name','Voltage Profile 40%','Position',[130 80 740 500]);
hold on; grid on; box on;
plot(bus_vec, V_none(idx40,:),    'o-','LineWidth',2,'MarkerSize',5,'MarkerFaceColor',c1,'Color',c1,'DisplayName','No Mitigation');
plot(bus_vec, V_curtail(idx40,:), 's-','LineWidth',2,'MarkerSize',5,'MarkerFaceColor',c2,'Color',c2,'DisplayName','Active Curtailment');
plot(bus_vec, V_eess(idx40,:),    'p-','LineWidth',2,'MarkerSize',6,'MarkerFaceColor',c3,'Color',c3,'DisplayName','Distributed EESS');
plot(bus_vec, V_static(idx40,:),  '^-','LineWidth',2,'MarkerSize',5,'MarkerFaceColor',c4,'Color',c4,'DisplayName','Static Q (PF=0.95)');
plot(bus_vec, V_droop(idx40,:),   'd-','LineWidth',2,'MarkerSize',5,'MarkerFaceColor',c5,'Color',c5,'DisplayName','Droop Q');
plot(bus_vec, V_adapt(idx40,:),   '*-','LineWidth',2,'MarkerSize',5,'MarkerFaceColor',c6,'Color',c6,'DisplayName','Adaptive Droop Q');
yline(Vmax,'r--','LineWidth',1.8,'DisplayName',sprintf('V_{max} = %.2f pu',Vmax));
yline(Vref,'k:','LineWidth',1.2,'DisplayName','V_{ref} = 1.00 pu');
xlabel('Bus Number','FontSize',12); ylabel('Voltage (p.u.)','FontSize',12);
title('Voltage Profile Along Feeder — 40% PV Penetration','FontSize',13,'FontWeight','bold');
subtitle('IEEE European LV Test Feeder');
legend('Location','best','FontSize',10);
xlim([1 n_bus]); ylim([0.96 1.12]); set(gca,'FontSize',12);

%% ---- Figure 3: Voltage Profile — 50% Penetration ------------------
figure('Name','Voltage Profile 50%','Position',[180 80 740 500]);
hold on; grid on; box on;
plot(bus_vec, V_none(idx50,:),    'o-','LineWidth',2,'MarkerSize',5,'MarkerFaceColor',c1,'Color',c1,'DisplayName','No Mitigation');
plot(bus_vec, V_curtail(idx50,:), 's-','LineWidth',2,'MarkerSize',5,'MarkerFaceColor',c2,'Color',c2,'DisplayName','Active Curtailment');
plot(bus_vec, V_eess(idx50,:),    'p-','LineWidth',2,'MarkerSize',6,'MarkerFaceColor',c3,'Color',c3,'DisplayName','Distributed EESS');
plot(bus_vec, V_static(idx50,:),  '^-','LineWidth',2,'MarkerSize',5,'MarkerFaceColor',c4,'Color',c4,'DisplayName','Static Q (PF=0.95)');
plot(bus_vec, V_droop(idx50,:),   'd-','LineWidth',2,'MarkerSize',5,'MarkerFaceColor',c5,'Color',c5,'DisplayName','Droop Q');
plot(bus_vec, V_adapt(idx50,:),   '*-','LineWidth',2,'MarkerSize',5,'MarkerFaceColor',c6,'Color',c6,'DisplayName','Adaptive Droop Q');
yline(Vmax,'r--','LineWidth',1.8,'DisplayName',sprintf('V_{max} = %.2f pu',Vmax));
yline(Vref,'k:','LineWidth',1.2,'DisplayName','V_{ref} = 1.00 pu');
xlabel('Bus Number','FontSize',12); ylabel('Voltage (p.u.)','FontSize',12);
title('Voltage Profile Along Feeder — 50% PV Penetration','FontSize',13,'FontWeight','bold');
subtitle('IEEE European LV Test Feeder');
legend('Location','best','FontSize',10);
xlim([1 n_bus]); ylim([0.96 1.12]); set(gca,'FontSize',12);

%% ---- Figure 4: Voltage Profile — 60% Penetration ------------------
figure('Name','Voltage Profile 60%','Position',[230 80 740 500]);
hold on; grid on; box on;
plot(bus_vec, V_none(idx60,:),    'o-','LineWidth',2,'MarkerSize',5,'MarkerFaceColor',c1,'Color',c1,'DisplayName','No Mitigation');
plot(bus_vec, V_curtail(idx60,:), 's-','LineWidth',2,'MarkerSize',5,'MarkerFaceColor',c2,'Color',c2,'DisplayName','Active Curtailment');
plot(bus_vec, V_eess(idx60,:),    'p-','LineWidth',2,'MarkerSize',6,'MarkerFaceColor',c3,'Color',c3,'DisplayName','Distributed EESS');
plot(bus_vec, V_static(idx60,:),  '^-','LineWidth',2,'MarkerSize',5,'MarkerFaceColor',c4,'Color',c4,'DisplayName','Static Q (PF=0.95)');
plot(bus_vec, V_droop(idx60,:),   'd-','LineWidth',2,'MarkerSize',5,'MarkerFaceColor',c5,'Color',c5,'DisplayName','Droop Q');
plot(bus_vec, V_adapt(idx60,:),   '*-','LineWidth',2,'MarkerSize',5,'MarkerFaceColor',c6,'Color',c6,'DisplayName','Adaptive Droop Q');
yline(Vmax,'r--','LineWidth',1.8,'DisplayName',sprintf('V_{max} = %.2f pu',Vmax));
yline(Vref,'k:','LineWidth',1.2,'DisplayName','V_{ref} = 1.00 pu');
xlabel('Bus Number','FontSize',12); ylabel('Voltage (p.u.)','FontSize',12);
title('Voltage Profile Along Feeder — 60% PV Penetration','FontSize',13,'FontWeight','bold');
subtitle('IEEE European LV Test Feeder');
legend('Location','best','FontSize',10);
xlim([1 n_bus]); ylim([0.96 1.12]); set(gca,'FontSize',12);

%% ---- Figure 5: Hosting Capacity — all 6 strategies ----------------
hosting_none    = get_max(V_none);
hosting_curtail = get_max(V_curtail);
hosting_eess    = get_max(V_eess);
hosting_static  = get_max(V_static);
hosting_droop   = get_max(V_droop);
hosting_adapt   = get_max(V_adapt);
hosting_values  = [hosting_none, hosting_curtail, hosting_eess, ...
                   hosting_static, hosting_droop, hosting_adapt];

figure('Name','Hosting Capacity','Position',[280 80 780 500]);
bh = bar(hosting_values, 0.6);
bh.FaceColor = 'flat';
bh.CData(1,:)=c1; bh.CData(2,:)=c2; bh.CData(3,:)=c3;
bh.CData(4,:)=c4; bh.CData(5,:)=c5; bh.CData(6,:)=c6;
set(gca,'XTickLabel',{'No Mitigation','Curtailment','Dist. EESS', ...
    'Static Q','Droop Q','Adapt. Droop Q'});
xtickangle(15);
ylabel('Maximum PV Penetration (%)','FontSize',12);
title('PV Hosting Capacity — All 6 Strategies','FontSize',13,'FontWeight','bold');
subtitle(sprintf('IEEE European LV Test Feeder  |  V_{max}=%.2f pu  |  *Curtailment/EESS operate at 40-60%% with active control',Vmax));
grid on; ylim([0 max(hosting_values)*1.35]);
for i = 1:6
    text(i, hosting_values(i)+0.8, sprintf('%d%%',hosting_values(i)), ...
        'HorizontalAlignment','center','FontSize',12,'FontWeight','bold');
end
set(gca,'FontSize',11);

%% ---- Figure 6: Voltage Violations — all 6 strategies --------------
figure('Name','Voltage Violations','Position',[330 80 760 460]);
viol = [sum(V_none>Vmax,2),    sum(V_curtail>Vmax,2),  sum(V_eess>Vmax,2), ...
        sum(V_static>Vmax,2),  sum(V_droop>Vmax,2),    sum(V_adapt>Vmax,2)];
b = bar(pen_levels, viol, 0.82);
b(1).FaceColor=c1; b(2).FaceColor=c2; b(3).FaceColor=c3;
b(4).FaceColor=c4; b(5).FaceColor=c5; b(6).FaceColor=c6;
legend({'No Mitigation','Curtailment','Dist. EESS','Static Q', ...
        'Droop Q','Adapt. Droop Q'},'Location','northwest','FontSize',10);
xlabel('PV Penetration (%)','FontSize',12);
ylabel('No. of Buses Exceeding V_{max}','FontSize',12);
title('Voltage Violations per Strategy','FontSize',13,'FontWeight','bold');
subtitle('IEEE European LV Test Feeder');
xticks(pen_levels); grid on; box on; set(gca,'FontSize',12);

%% ---- Figure 7: Curtailment vs EESS — Energy Wasted vs Stored ------
figure('Name','Curtailment vs EESS','Position',[380 80 720 460]);
hold on; grid on; box on;
b7 = bar(pen_levels, [P_curtailed*Sbase_kVA; P_stored_eess*Sbase_kVA]', 0.65);
b7(1).FaceColor=c2; b7(2).FaceColor=c3;
legend({'Active Curtailment — Energy WASTED (lost forever)', ...
        'Distributed EESS  — Energy STORED (used in evening)'}, ...
    'Location','northwest','FontSize',10);
xlabel('PV Penetration (%)','FontSize',12);
ylabel('Active Power (kW)','FontSize',12);
title('Same Voltage Control — Very Different Energy Outcome','FontSize',13,'FontWeight','bold');
subtitle('Both keep V \leq 1.05 pu | Curtailment wastes energy | EESS stores it');
xticks(pen_levels); box on; set(gca,'FontSize',12);

%% ---- Figure 8: EESS Battery Charging per House --------------------
figure('Name','EESS Charging','Position',[430 80 720 460]);
yyaxis left
hBar = bar(pen_levels, Pb_each_log, 0.5, 'FaceColor',c3,'FaceAlpha',0.80, ...
    'DisplayName','Charging Power per House (kW)');
hold on;
hLine = yline(Pbatt_max*Sbase_kVA,'--','Color',[0.85 0.65 0.00],'LineWidth',1.8, ...
    'DisplayName',sprintf('P_{batt,max} = %.2f kW (battery limit)',Pbatt_max*Sbase_kVA));
ylabel('Charging Power per House (kW)','FontSize',12);
ylim([0 Pbatt_max*Sbase_kVA*1.4]);
yyaxis right
hPct = plot(pen_levels, Pb_each_log/(Pbatt_max*Sbase_kVA)*100, ...
    'ko-','LineWidth',2,'MarkerSize',7,'MarkerFaceColor','k', ...
    'DisplayName','Battery Usage (% of P_{batt,max})');
ylabel('Battery Usage (% of P_{batt,max})','FontSize',12);
ylim([0 140]);
xlabel('PV Penetration (%)','FontSize',12);
title('EESS Battery Charging Power vs PV Penetration','FontSize',13,'FontWeight','bold');
subtitle(sprintf('P_{batt,max}=%.2f kW/house  |  P_{load}=%.2f kW/house  |  Ratio=%.2fx', ...
    Pbatt_max*Sbase_kVA, P_load*Sbase_kVA, Pbatt_max/P_load));
xticks(pen_levels); grid on;
legend([hBar, hLine, hPct], ...
    {'Charging Power per House (kW)', ...
     sprintf('P_{batt,max} = %.2f kW (battery limit)', Pbatt_max*Sbase_kVA), ...
     'Battery Usage (% of P_{batt,max})'}, ...
    'Location','northwest','FontSize',10);
set(gca,'FontSize',12);

%% ---- Figure 9: Reactive Power Usage (Strategies 4, 5, 6) ----------
figure('Name','Q Usage','Position',[480 80 720 460]);
hold on; grid on; box on;
plot(pen_levels, Q_used_static*Sbase_kVA,'^-','LineWidth',2.2,'MarkerSize',8,'MarkerFaceColor',c4,'Color',c4,'DisplayName','Static Q  (always ON)');
plot(pen_levels, Q_used_droop*Sbase_kVA, 'd-','LineWidth',2.2,'MarkerSize',8,'MarkerFaceColor',c5,'Color',c5,'DisplayName','Droop Q  (fixed gain)');
plot(pen_levels, Q_used_adapt*Sbase_kVA, '*-','LineWidth',2.2,'MarkerSize',8,'MarkerFaceColor',c6,'Color',c6,'DisplayName','Adaptive Droop Q');
xlabel('PV Penetration (%)','FontSize',12);
ylabel('Total Q Absorbed (kVAR)','FontSize',12);
title('Reactive Power Usage Comparison','FontSize',13,'FontWeight','bold');
subtitle('IEEE European LV Test Feeder');
legend('Location','northwest','FontSize',10);
xticks(pen_levels); grid on; set(gca,'FontSize',12);

%% ---- Figure 10: Active Curtailment Energy Loss --------------------
figure('Name','Curtailment Loss','Position',[530 80 700 450]);
bar(pen_levels, P_curtailed*Sbase_kVA, 0.55, 'FaceColor',c2,'FaceAlpha',0.85);
xlabel('PV Penetration (%)','FontSize',12);
ylabel('Curtailed PV Power (kW)','FontSize',12);
title('Active Curtailment: Solar Energy Wasted','FontSize',13,'FontWeight','bold');
subtitle('IEEE European LV Test Feeder');
xticks(pen_levels); grid on; box on; set(gca,'FontSize',12);

%% ---- Figure 11: Adaptive Droop Gain vs Penetration ----------------
figure('Name','Adaptive Droop Gain','Position',[580 80 660 440]);
Kq_adapt_curve = Kq * (1 + alpha * pen_levels/100);
plot(pen_levels, Kq_adapt_curve,'o-','LineWidth',2.2,'MarkerSize',8,'MarkerFaceColor',c6,'Color',c6,'DisplayName','Adaptive K_q');
hold on;
yline(Kq,'r--','LineWidth',1.8,'DisplayName',sprintf('Fixed Droop K_q = %.2f',Kq));
xlabel('PV Penetration (%)','FontSize',12);
ylabel('Droop Gain K_q','FontSize',12);
title('Adaptive Droop Gain vs PV Penetration','FontSize',13,'FontWeight','bold');
subtitle(sprintf('K_q^{adapt} = K_q(1+\\alpha\\cdot pen),  \\alpha=%.1f  |  Q_{max}=%.2f kVAR (IEEE 1547-2018)', ...
    alpha, Qmax_inv*Sbase_kVA));
legend('Location','northwest','FontSize',11);
xticks(pen_levels); grid on; box on; set(gca,'FontSize',12);

%% ============================================================
%  SECTION 6: CONSOLE SUMMARY
%% ============================================================

fprintf('\n=====================================================\n');
fprintf('  RESULTS SUMMARY — ALL 6 STRATEGIES\n');
fprintf('  IEEE European LV Test Feeder\n');
fprintf('  R/X=%.1f | %d buses | Sbase=%d kVA | Vmax=%.2f pu\n', ...
    R/X, n_bus, Sbase_kVA, Vmax);
fprintf('=====================================================\n');
fprintf('  %-26s  Hosting\n','Strategy');
fprintf('  %-26s  -------\n', repmat('-',1,26));
fprintf('  %-26s  %d%%\n','1. No Mitigation',       hosting_none);
fprintf('  %-26s  %d%%\n','2. Active Curtailment',   hosting_curtail);
fprintf('  %-26s  %d%% (stores energy, not wastes)\n','3. Distributed EESS', hosting_eess);
fprintf('  %-26s  %d%%\n','4. Static Q (PF=0.95)',   hosting_static);
fprintf('  %-26s  %d%%\n','5. Droop Q',              hosting_droop);
fprintf('  %-26s  %d%%\n','6. Adaptive Droop Q',     hosting_adapt);
fprintf('=====================================================\n');
fprintf('  Max voltage at feeder end — 40%% / 50%% / 60%% pen:\n');
fprintf('  No Mitigation  : %.4f / %.4f / %.4f pu\n', V_none(idx40,end),    V_none(idx50,end),    V_none(idx60,end));
fprintf('  Curtailment    : %.4f / %.4f / %.4f pu\n', V_curtail(idx40,end), V_curtail(idx50,end), V_curtail(idx60,end));
fprintf('  Dist. EESS     : %.4f / %.4f / %.4f pu\n', V_eess(idx40,end),    V_eess(idx50,end),    V_eess(idx60,end));
fprintf('  Static Q       : %.4f / %.4f / %.4f pu\n', V_static(idx40,end),  V_static(idx50,end),  V_static(idx60,end));
fprintf('  Droop Q        : %.4f / %.4f / %.4f pu\n', V_droop(idx40,end),   V_droop(idx50,end),   V_droop(idx60,end));
fprintf('  Adaptive Droop : %.4f / %.4f / %.4f pu\n', V_adapt(idx40,end),   V_adapt(idx50,end),   V_adapt(idx60,end));
fprintf('=====================================================\n');
fprintf('  EESS Battery (per house): P_load=%.2f kW | Pbatt_max=%.3f kW\n', ...
    P_load*Sbase_kVA, Pbatt_max*Sbase_kVA);
fprintf('  At 40%% pen: %.4f kW charged  (%.1f%% of capacity)\n', ...
    Pb_each_log(idx40), Pb_each_log(idx40)/(Pbatt_max*Sbase_kVA)*100);
fprintf('  At 50%% pen: %.4f kW charged  (%.1f%% of capacity)\n', ...
    Pb_each_log(idx50), Pb_each_log(idx50)/(Pbatt_max*Sbase_kVA)*100);
fprintf('  At 60%% pen: %.4f kW charged  (%.1f%% of capacity)\n', ...
    Pb_each_log(idx60), Pb_each_log(idx60)/(Pbatt_max*Sbase_kVA)*100);
fprintf('=====================================================\n\n');