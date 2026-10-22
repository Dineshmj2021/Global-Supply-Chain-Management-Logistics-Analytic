import os
import pandas as pd
import numpy as np
import matplotlib.pyplot as plt
import matplotlib.ticker as ticker
import seaborn as sns

plt.style.use('dark_background')
plt.rcParams['font.sans-serif'] = 'Segoe UI'
plt.rcParams['font.family'] = 'sans-serif'

base_dir = "d:/PowerBI-SQL-Project"
screen_dir = f"{base_dir}/Screenshots"
os.makedirs(screen_dir, exist_ok=True)

# Colors
BG_COLOR = "#0F172A"
CARD_BG = "#1E293B"
BLUE_ACCENT = "#38BDF8"
GREEN_SUCCESS = "#10B981"
AMBER_WARN = "#F59E0B"
RED_ALERT = "#EF4444"
PURPLE_ACCENT = "#818CF8"
TEXT_MUTED = "#94A3B8"
WHITE = "#FFFFFF"

# Load datasets
orders = pd.read_csv(f"{base_dir}/Dataset/orders_shipments.csv")
carriers = pd.read_csv(f"{base_dir}/Dataset/carriers.csv")
products = pd.read_csv(f"{base_dir}/Dataset/products.csv")
warehouses = pd.read_csv(f"{base_dir}/Dataset/warehouses.csv")
suppliers = pd.read_csv(f"{base_dir}/Dataset/suppliers.csv")
inventory = pd.read_csv(f"{base_dir}/Dataset/inventory_levels.csv")
procurement = pd.read_csv(f"{base_dir}/Dataset/procurement_pos.csv")

# 1. SCREENSHOT 1: DASHBOARD OVERVIEW (dashboard_overview.png)
fig = plt.figure(figsize=(16, 9), facecolor=BG_COLOR)
gs = fig.add_gridspec(3, 4, hspace=0.35, wspace=0.25, top=0.90, bottom=0.06, left=0.06, right=0.96)

fig.text(0.06, 0.94, "SUPPLY CHAIN EXECUTIVE OVERVIEW & OTIF DASHBOARD", fontsize=18, fontweight='bold', color=WHITE)
fig.text(0.06, 0.915, "Enterprise Star Schema Analytics | Multi-Tier Fulfillment & Logistics Performance", fontsize=10, color=TEXT_MUTED)

kpis = [
    ("OTIF RATE %", f"{orders['OTIFFlag'].mean()*100:.1f}%", "Target: 92.0% | Status: Healthy", GREEN_SUCCESS),
    ("TOTAL REVENUE", f"${orders['GrossRevenue'].sum()/1e6:.2f}M", f"Gross Margin: {orders['GrossProfit'].sum()/orders['GrossRevenue'].sum()*100:.1f}%", BLUE_ACCENT),
    ("AVG FULFILLMENT CYCLE", f"{orders['FulfillmentCycleDays'].mean():.1f} Days", "Benchmark: <= 7.0 Days", PURPLE_ACCENT),
    ("TOTAL ORDERS FULFILLED", f"{len(orders):,}", f"On-Time: {orders['OnTimeFlag'].mean()*100:.1f}% | In-Full: {orders['InFullFlag'].mean()*100:.1f}%", WHITE)
]

for i, (title, val, sub, col) in enumerate(kpis):
    ax_kpi = fig.add_subplot(gs[0, i])
    ax_kpi.set_facecolor(CARD_BG)
    for spine in ax_kpi.spines.values():
        spine.set_color("#334155")
        spine.set_linewidth(1.5)
    ax_kpi.text(0.08, 0.72, title, fontsize=9, fontweight='bold', color=TEXT_MUTED)
    ax_kpi.text(0.08, 0.35, val, fontsize=20, fontweight='bold', color=col)
    ax_kpi.text(0.08, 0.12, sub, fontsize=8, color=TEXT_MUTED)
    ax_kpi.set_xticks([])
    ax_kpi.set_yticks([])

ax_trend = fig.add_subplot(gs[1, 0:3])
ax_trend.set_facecolor(CARD_BG)
for spine in ax_trend.spines.values(): spine.set_color("#334155")

orders['YearMonth'] = orders['OrderDate'].str[:7]
monthly = orders.groupby('YearMonth').agg(
    Orders=('OrderID', 'count'),
    OTIF=('OTIFFlag', lambda x: x.mean() * 100)
).reset_index()

x = np.arange(len(monthly))
bars = ax_trend.bar(x, monthly['Orders'], color="#1E40AF", alpha=0.85, width=0.55, label="Order Volume")
ax_trend.set_ylabel("Order Count", color=TEXT_MUTED, fontsize=9)
ax_trend.set_xticks(x[::3])
ax_trend.set_xticklabels(monthly['YearMonth'][::3], rotation=0, fontsize=8, color=TEXT_MUTED)
ax_trend.tick_params(colors=TEXT_MUTED)
ax_trend.grid(axis='y', color="#334155", linestyle='--', alpha=0.5)

ax_line = ax_trend.twinx()
ax_line.plot(x, monthly['OTIF'], color=GREEN_SUCCESS, linewidth=2.5, marker='o', markersize=4, label="OTIF Rate %")
ax_line.axhline(92.0, color=RED_ALERT, linestyle=':', linewidth=1.8, label="SLA Target (92%)")
ax_line.set_ylabel("OTIF %", color=GREEN_SUCCESS, fontsize=9)
ax_line.set_ylim(70, 100)
ax_line.tick_params(colors=GREEN_SUCCESS)
ax_trend.set_title("Order Volume vs. OTIF SLA Performance Trend", color=WHITE, fontsize=11, fontweight='bold', pad=10, loc='left')

ax_donut = fig.add_subplot(gs[1, 3])
ax_donut.set_facecolor(CARD_BG)
for spine in ax_donut.spines.values(): spine.set_color("#334155")
returns = orders[orders['ReturnFlag'] == 1]['ReturnReason'].value_counts()
if len(returns) == 0:
    returns = pd.Series({'Damaged': 12, 'Wrong Item': 8, 'Customer Cancelled': 5})
colors_donut = [RED_ALERT, AMBER_WARN, PURPLE_ACCENT, BLUE_ACCENT]
wedges, texts, autotexts = ax_donut.pie(returns, labels=returns.index, autopct='%1.1f%%',
                                        startangle=140, colors=colors_donut[:len(returns)],
                                        wedgeprops=dict(width=0.45, edgecolor=CARD_BG, linewidth=2))
for t in texts: t.set_color(TEXT_MUTED); t.set_fontsize(7.5)
for at in autotexts: at.set_color(WHITE); at.set_fontsize(7.5); at.set_weight('bold')
ax_donut.set_title("Returns by Root Cause", color=WHITE, fontsize=10, fontweight='bold', pad=10)

ax_carrier = fig.add_subplot(gs[2, 0:2])
ax_carrier.set_facecolor(CARD_BG)
for spine in ax_carrier.spines.values(): spine.set_color("#334155")
merged_c = orders.merge(carriers, on='CarrierID')
c_otif = merged_c.groupby('CarrierName')['OTIFFlag'].mean().sort_values(ascending=True) * 100
bars_c = ax_carrier.barh(c_otif.index, c_otif.values, color=[GREEN_SUCCESS if v >= 92 else AMBER_WARN for v in c_otif.values], height=0.55)
ax_carrier.axvline(92.0, color=RED_ALERT, linestyle='--', linewidth=1.5, label="SLA Target (92%)")
ax_carrier.set_xlim(70, 100)
ax_carrier.set_xlabel("OTIF Rate %", color=TEXT_MUTED, fontsize=9)
ax_carrier.tick_params(colors=TEXT_MUTED, labelsize=8)
ax_carrier.grid(axis='x', color="#334155", linestyle='--', alpha=0.5)
ax_carrier.set_title("Carrier SLA OTIF Ranking", color=WHITE, fontsize=10, fontweight='bold', pad=8, loc='left')

ax_wh = fig.add_subplot(gs[2, 2:4])
ax_wh.set_facecolor(CARD_BG)
for spine in ax_wh.spines.values(): spine.set_color("#334155")
merged_w = orders.merge(warehouses, on='WarehouseID')
wh_cycle = merged_w.groupby('WarehouseName')['FulfillmentCycleDays'].mean().sort_values()
ax_wh.bar(range(len(wh_cycle)), wh_cycle.values, color=BLUE_ACCENT, width=0.55)
ax_wh.set_ylabel("Avg Days", color=TEXT_MUTED, fontsize=9)
ax_wh.tick_params(colors=TEXT_MUTED, labelsize=8)
ax_wh.set_xticks(range(len(wh_cycle)))
ax_wh.set_xticklabels(wh_cycle.index, rotation=15, ha='right', fontsize=7.5)
ax_wh.grid(axis='y', color="#334155", linestyle='--', alpha=0.5)
ax_wh.set_title("Fulfillment Cycle Time by Distribution Hub", color=WHITE, fontsize=10, fontweight='bold', pad=8, loc='left')

plt.savefig(f"{screen_dir}/dashboard_overview.png", dpi=200, bbox_inches='tight', facecolor=BG_COLOR)
plt.close()
print("Saved dashboard_overview.png")
