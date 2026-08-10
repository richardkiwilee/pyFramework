# -*- coding: utf-8 -*-
"""Generate buildings.json for Total War: Three Kingdoms (全面战争：三国)."""
import json

B = []  # buildings list
seq = [0]
def bld(name_zh, name_en, btype, tier, upgrades_from, upgrades_to,
        cost, time, upkeep, effects, requirements, faction="all", desc=""):
    seq[0] += 1
    B.append({
        "id": "bld_%03d" % seq[0],
        "name_zh": name_zh,
        "name_en": name_en,
        "type": btype,
        "tier": tier,
        "upgrades_from": upgrades_from,
        "upgrades_to": upgrades_to,
        "construction_cost": cost,
        "construction_time": time,
        "upkeep": upkeep,
        "effects": effects,
        "requirements": requirements,
        "faction": faction,
        "description": desc,
    })

# ============================================================
# 1. 郡国治所 Settlement Administration (10 levels)
# ============================================================
cap = [
    ("小镇", "Small Town", 1000, 4, 0, "+2 声望 prestige; 人口上限+200K; 1个建筑栏位; +10粮食储备上限", []),
    ("城镇", "Town", 1500, 4, 0, "+4 声望; 人口上限+300K; 2个建筑栏位; 开始拥有守军(初始防御)", ["人口达到一定水平"]),
    ("大镇", "Large Town", 2000, 4, 0, "+8 声望; 人口上限+400K; +25农民收入; +25%商业收入", []),
    ("小县城", "Small City", 3000, 6, 0, "+12 声望; 人口上限+800K; 3个建筑栏位; 粮食-2; 拥有城墙; +25商业收入; 守军7", ["改革: 黄门宦官(Eunuch Secretaries)"]),
    ("县城", "City", 4000, 6, 0, "+16 声望; 人口上限+1M; 4个建筑栏位; 粮食-6", []),
    ("大县城", "Large City", 5000, 6, 0, "+20 声望; 人口上限+1.5M; 4个建筑栏位; 粮食-10; +50农民收入; +50商业收入(派系)", []),
    ("小城", "Small Regional City", 6500, 8, 0, "+20~25 声望; 人口上限+1.5~2M; 5个建筑栏位; 粮食-16; 腐败+5%; 公共秩序-5; +50%商业收入; 高级箭塔", []),
    ("城市", "Regional City", 8000, 8, 0, "+30 声望; 人口上限+3M; 6个建筑栏位; 粮食-24; +75农民收入; 可升级为都城", []),
    ("大城", "Large Regional City", 10000, 8, 0, "+40 声望; 人口上限+4M; 6个建筑栏位; 粮食-34; 腐败+15%; 公共秩序-15; +75%商业收入", []),
    ("都城", "Imperial City", 12000, 10, 0, "+50 声望; 人口上限+7.5M; 6个建筑栏位; 粮食-46; +100农民收入; +150%商业收入; 每派系仅一座", ["仅1座/派系"]),
]
for i, (zh, en, cost, tm, up, fx, req) in enumerate(cap):
    bld(zh, en, "government", i+1,
        None if i == 0 else cap[i-1][0], None if i == len(cap)-1 else cap[i+1][0],
        cost, tm, up, [fx], req, "all", "郡国治所(Settlement Administration)链第%d级，决定建筑栏位/人口上限/守军" % (i+1))

# ============================================================
# 2. 民力 Labour
# ============================================================
lab = [
    ("流人劳工营地", "Drifter Workforce Camp", 700, 1, 0, ["人口增长+4K(本地郡县)", "学习与市场建筑建造成本-10%"], []),
    ("临时劳工居所", "Temporary Labour Housing", 1150, 1, 0, ["人口增长+12K(本地)", "相邻郡县人口迁移-1K"], []),
    ("征募劳工居所", "Labourer Conscription Housing", 1800, 1, 0, ["人口增长+25K(本地)", "相邻郡县人口迁移-2K"], ["改革: 劝奴(Slave Mobilisation)"]),
    ("永久劳工居所", "Permanent Labour Housing", 3050, 1, 0, ["人口增长+50K(本地)", "相邻-4K", "提供匠师资源"], ["改革: 考工室(Office of Arts & Crafts)"]),
    ("劳工署", "Office of Works", 5400, 1, 0, ["人口增长+100K(本地)", "相邻-6K", "学习与市场建筑建造成本-15%"], ["改革: 官营垄断(State Monopolies)"]),
    ("矿业署", "Bureau of Mining Subsidiaries", 2800, 1, 0, ["人口增长+40K(本地)", "工业收入+25%(本地)"], ["铁矿+食盐资源", "改革: 辘轳采矿(Shaft Mining)", "解锁手工业者"]),
    ("官营采矿书", "Bureau of State Mining Expeditions", 3800, 1, 0, ["人口增长+80K(本地)", "工业收入+40%(本地)"], ["改革: 排气室(Ventilation Shafts)"]),
]
for i, (zh, en, cost, tm, up, fx, req) in enumerate(lab):
    tier_map = {"永久劳工居所": 4, "劳工署": 5, "矿业署": 4, "官营采矿书": 5}
    tier = tier_map.get(zh, i+1)
    up_from = None
    if zh == "永久劳工居所": up_from = "征募劳工居所"
    if zh == "劳工署": up_from = "永久劳工居所"
    if zh == "矿业署": up_from = "征募劳工居所"
    if zh == "官营采矿书": up_from = "矿业署"
    bld(zh, en, "income", tier, up_from, [], cost, tm, up, fx, req, "all",
        "民力(Labour)链：人口增长核心，4级分商业/矿业两路；矿业路需铁矿与食盐")

# ============================================================
# 3. 官坊 State Workshops
# ============================================================
sw = [
    ("官坊", "State Workshops", 1250, 1, 0, ["工业收入+100(本地)", "学习与市场建筑建造成本-10%", "改革度-2(本地郡县)"], ["改革: 陶砖(Terra-cotta Brickwork)"]),
    ("公共坊", "Communal Workshops", 2100, 1, 0, ["工业收入+200(本地)", "学习与市场建筑建造成本-10%", "改革度-4"], []),
    ("公家工坊", "Government Workshops", 2950, 1, 0, ["工业收入+300(本地)", "学习与市场建筑建造成本-10%", "改革度-6"], ["改革: 货币经济(Money Economy)"]),
    ("郡国工坊", "Government Provincial Workshops", 3800, 1, 0, ["工业收入+400(本地)", "学习与市场建筑建造成本-10%", "解锁手工业者"], ["改革: 考工室(Office of Arts & Crafts)"]),
    ("将作监", "Grand State Workshops", 4650, 1, 0, ["工业收入+500(本地)", "学习与市场建筑建造成本-15%"], ["改革: 官营垄断(State Monopolies)"]),
    ("钟官署", "Currency Inspector Office", 2950, 1, 0, ["工业收入+100", "本地腐败-10%"], ["改革: 货币经济(Money Economy)"]),
    ("铸币厂", "Coin Maker", 3800, 1, 0, ["工业收入+200", "相邻郡国腐败-10%"], ["改革: 考工室", "铜矿资源"]),
    ("大型官营铸币厂", "Grand Treasury Mint", 4650, 1, 0, ["工业收入+300", "相邻郡国腐败-15%"], ["改革: 官营垄断"]),
]
for i, (zh, en, cost, tm, up, fx, req) in enumerate(sw):
    tier_map = {"官坊": 1, "公共坊": 2, "公家工坊": 3, "郡国工坊": 4, "将作监": 5, "钟官署": 3, "铸币厂": 4, "大型官营铸币厂": 5}
    tier = tier_map.get(zh, i+1)
    up_from = None
    if zh in ("公家工坊", "钟官署"): up_from = "公共坊"
    if zh == "郡国工坊": up_from = "公家工坊"
    if zh == "将作监": up_from = "郡国工坊"
    if zh == "铸币厂": up_from = "钟官署"
    if zh == "大型官营铸币厂": up_from = "铸币厂"
    bld(zh, en, "income", tier, up_from, [], cost, tm, up, fx, req, "all",
        "官坊(State Workshops)链：工业收入；3级分公家工坊(产值)与钟官署(反腐)两路")

# ============================================================
# 4. 手工作坊 Private Workshops
# ============================================================
pw = [
    ("手工作坊", "Private Workshops", 650, 1, 0, ["商业收入+25%", "工业收入+5%", "学习与市场建筑建造成本-10%"], []),
    ("工棚", "Craftsmen Shacks", 1050, 1, 0, ["商业收入+50%", "工业收入+10%"], []),
    ("工坊", "Craftsmen Workshops", 1450, 1, 0, ["商业收入+75%", "工业收入+15%"], ["改革: 货币经济"]),
    ("匠工坊", "Artisan Workshops", 2200, 1, 0, ["商业收入+100%", "工业收入+20%", "解锁匠师"], ["改革: 整顿商贾(Regulate Commerce)"]),
    ("大匠坊", "Master Artisans", 3300, 1, 0, ["商业收入+125%", "工业收入+20%"], ["改革: 行肆市列(Market Streets)"]),
    ("漆器将作监", "Master Lacquerware Artisans", 3600, 1, 0, ["商业收入+190%", "工业收入+40%"], ["改革: 行肆市列", "木材资源"]),
]
for i, (zh, en, cost, tm, up, fx, req) in enumerate(pw):
    tier_map = {"手工作坊": 1, "工棚": 2, "工坊": 3, "匠工坊": 4, "大匠坊": 5, "漆器将作监": 5}
    tier = tier_map.get(zh, i+1)
    up_from = None
    if zh == "工棚": up_from = "手工作坊"
    if zh == "工坊": up_from = "工棚"
    if zh == "匠工坊": up_from = "工坊"
    if zh in ("大匠坊", "漆器将作监"): up_from = "匠工坊"
    bld(zh, en, "income", tier, up_from, [], cost, tm, up, fx, req, "all",
        "手工作坊(Private Workshops)链：以百分比提升工商业收入")

# ============================================================
# 5. 官府支持 Government Support
# ============================================================
gs = [
    ("流人农营", "Drifter Farming Camp", 700, 1, 0, ["粮食产量+25%", "农民收入+10%", "军事建筑建造成本-10%"], []),
    ("农工营", "Farm Labourer Camp", 1150, 1, 0, ["粮食产量+50%", "农民收入+25%"], []),
    ("劳工署", "Workforce Distribution Office", 1800, 1, 0, ["农民收入+50%"], []),
    ("郡国水利", "Commandery Irrigation Works", 2000, 3, 20, ["粮食产量+75%", "农民收入+75%"], ["改革: 水利灌溉(Irrigation)", "谷物资源"]),
    ("大型灌渠", "Grand Irrigation Canals", 3800, 3, 40, ["粮食产量+100%", "农民收入+100%"], ["改革: 密植(Intensive Planting)", "谷物资源"]),
    ("农具库", "Farm Supply Storage", 1800, 1, 0, ["粮食产量+70%"], []),
    ("配给所", "Farm Tool Distribution", 2000, 3, 20, ["农民收入+35%"], ["改革: 郡国铁具锻炉(County Iron Forges)", "工具资源"]),
    ("扇车工坊", "Winnowing Machine Workshop", 3800, 3, 40, ["粮食产量+150%"], ["改革: 扇车(Winnowing Machines)", "工具资源", "需要区域性城市"]),
]
for i, (zh, en, cost, tm, up, fx, req) in enumerate(gs):
    tier_map = {"流人农营": 1, "农工营": 2, "劳工署": 3, "郡国水利": 4, "大型灌渠": 5, "农具库": 3, "配给所": 4, "扇车工坊": 5}
    tier = tier_map.get(zh, i+1)
    up_from = None
    if zh in ("劳工署", "农具库"): up_from = "农工营"
    if zh == "郡国水利": up_from = "劳工署"
    if zh == "大型灌渠": up_from = "郡国水利"
    if zh == "配给所": up_from = "农具库"
    if zh == "扇车工坊": up_from = "配给所"
    bld(zh, en, "food", tier, up_from, [], cost, tm, up, fx, req, "all",
        "官府支持(Government Support)链：百分比提升粮食与农民收入")

# ============================================================
# 6. 拓土 Land Development
# ============================================================
ld = [
    ("稽田署", "Agricultural Taxation Office", 600, 1, 0, ["粮食+1", "农民收入+70", "军事建筑建造成本-10%"], []),
    ("度田署", "Agricultural Ministry", 900, 1, 0, ["粮食+2", "农民收入+90"], []),
    ("浇灌农田", "Irrigation Fields", 1200, 1, 0, ["粮食+3", "农民收入+110"], []),
    ("农耕田庄", "Farming Estates", 1800, 1, 0, ["粮食+4", "农民收入+130"], ["改革: 租佃制度(Tenant Farming)"]),
    ("豪强田庄", "Magnate Estates", 3000, 1, 0, ["粮食+5", "农民收入+150"], ["改革: 地主豪族(Landlord Magnates)"]),
    ("食物市场", "Food Market", 1200, 1, 0, ["农民收入+220", "粮食-6", "军事建筑建造成本-10%", "改革度+3"], ["改革: 农书(Treatise on Agriculture)"]),
    ("食物市集", "Food Bazaar", 1800, 1, 0, ["农民收入+250", "粮食-12"], []),
    ("大型食物市集", "Grand Food Market", 3000, 1, 0, ["农民收入+280", "粮食-18"], ["改革: 密植(Intensive Planting)"]),
    ("郡府牛马市", "County Livestock Market", 3600, 1, 0, ["农民收入+300", "粮食-24"], ["改革: 密植", "畜牧资源", "巨贾资源"]),
]
for i, (zh, en, cost, tm, up, fx, req) in enumerate(ld):
    tier_map = {"稽田署": 1, "度田署": 2, "浇灌农田": 3, "农耕田庄": 4, "豪强田庄": 5, "食物市场": 3, "食物市集": 4, "大型食物市集": 5, "郡府牛马市": 5}
    tier = tier_map.get(zh, i+1)
    up_from = None
    if zh == "度田署": up_from = "稽田署"
    if zh in ("浇灌农田", "食物市场"): up_from = "度田署"
    if zh == "农耕田庄": up_from = "浇灌农田"
    if zh == "豪强田庄": up_from = "农耕田庄"
    if zh == "食物市集": up_from = "食物市场"
    if zh in ("大型食物市集", "郡府牛马市"): up_from = "食物市集"
    bld(zh, en, "food", tier, up_from, [], cost, tm, up, fx, req, "all",
        "拓土(Land Development)链：直接粮食+农民收入；3级分田庄(粮食)与市场(卖粮换钱)两路")

# ============================================================
# 7. 粮食储备 Grain Storage
# ============================================================
gr = [
    ("谷仓", "Grain Store", 600, 1, 0, ["公共秩序+2", "粮食储备上限+25", "军事建筑建造成本-10%"], []),
    ("筒仓", "Grain Silo", 1200, 1, 0, ["公共秩序+4", "粮食储备上限+40"], ["解锁改革: 平准仓(Ever-level Granaries)"]),
    ("粮库", "Grain Depot", 1800, 1, 0, ["公共秩序+6", "粮食储备上限+60"], []),
    ("邸阁", "Granary", 2400, 1, 0, ["公共秩序+8", "粮食储备上限+80"], ["改革: 平准仓"]),
    ("大型邸阁", "Grand Granary", 3000, 1, 0, ["公共秩序+10", "粮食储备上限+120", "军事建筑建造成本-15%"], ["改革: 军屯(Military Colonies)"]),
]
for i, (zh, en, cost, tm, up, fx, req) in enumerate(gr):
    bld(zh, en, "food", i+1, None if i == 0 else gr[i-1][0],
        None if i == len(gr)-1 else gr[i+1][0], cost, tm, up, fx, req, "all",
        "粮食储备(Grain Storage)链：增加粮食储备上限与公共秩序")

# ============================================================
# 8. 港口 Harbour
# ============================================================
hb = [
    ("鱼湾", "Jetties", 1700, 1, 0, ["粮食+2(渔业)", "商业收入+40", "农业建筑建造成本-10%"], ["靠河/海"]),
    ("渔港", "Pier", 2500, 1, 0, ["粮食+3(渔业)", "商业收入+70"], []),
    ("贩渔港", "Fish Trader", 3300, 1, 0, ["粮食+4(渔业)", "商业收入+100"], []),
    ("渔港口岸", "Fishing Port", 4100, 1, 0, ["粮食+5(渔业)", "商业收入+130"], ["改革: 外邦使者(Foreign Envoys)"]),
    ("大型渔港口岸", "Grand Fishing Port", 4900, 1, 0, ["粮食+6(渔业)", "商业收入+160", "农业建筑建造成本-15%"], ["改革: 大鸿胪(Grand Herald)"]),
    ("商港", "Harbour Trader", 3300, 1, 0, ["粮食+3(渔业)", "商业收入+110", "商业收入+10%(派系)", "农业建筑建造成本-10%"], []),
    ("商港口岸", "Trade Port", 4100, 1, 0, ["商业收入+130", "商业收入+15%(派系)"], ["改革: 外邦使者"]),
    ("大型商港", "Grand Trading Post", 4900, 1, 0, ["商业收入+160", "商业收入+20%(派系)", "农业建筑建造成本-15%"], ["改革: 大鸿胪"]),
    ("香药商埠", "Spice Trading Port", 5200, 1, 0, ["商业收入+200", "香药收入提升(派系)", "贸易影响力+15%"], ["改革: 大鸿胪", "香药资源"]),
]
for i, (zh, en, cost, tm, up, fx, req) in enumerate(hb):
    tier_map = {"鱼湾": 1, "渔港": 2, "贩渔港": 3, "渔港口岸": 4, "大型渔港口岸": 5, "商港": 3, "商港口岸": 4, "大型商港": 5, "香药商埠": 5}
    tier = tier_map.get(zh, i+1)
    up_from = None
    if zh == "渔港": up_from = "鱼湾"
    if zh in ("贩渔港", "商港"): up_from = "渔港"
    if zh == "渔港口岸": up_from = "贩渔港"
    if zh == "大型渔港口岸": up_from = "渔港口岸"
    if zh == "商港口岸": up_from = "商港"
    if zh in ("大型商港", "香药商埠"): up_from = "商港口岸"
    bld(zh, en, "income", tier, up_from, [], cost, tm, up, fx, req, "all",
        "港口(Harbour)链：仅限靠水城市；渔业/商业两路。孙坚派系每座大型商港额外提供派系商业收入+25%")

# ============================================================
# 9. 市肆 Inn
# ============================================================
inn = [
    ("驿站", "Horse Exchange", 700, 1, 0, ["商业收入+100", "商业收入+10%", "农业建筑建造成本-10%"], ["解锁改革: 六博(Liu Bo)"]),
    ("邮驿", "Mail Post", 1150, 1, 0, ["商业收入+120", "商业收入+25%"], []),
    ("客舍", "Lodge", 1800, 1, 0, ["商业收入+140", "商业收入+50%"], []),
    ("客栈", "Guest House", 2600, 1, 0, ["商业收入+160", "商业收入+75%"], ["改革: 六博"]),
    ("豪华客栈", "Grand Guest House", 3400, 1, 0, ["商业收入+200", "商业收入+100%", "农业建筑建造成本-15%"], ["改革: 围棋(Go)"]),
    ("茶室", "Tea Parlour", 1800, 1, 0, ["商业收入+150", "商业收入+30%"], ["茶叶资源"]),
    ("茶馆", "Tea House", 2600, 1, 0, ["商业收入+200", "商业收入+50%"], ["改革: 六博", "茶叶资源"]),
    ("大型茶馆", "Grand Tea House", 3400, 1, 0, ["商业收入+250", "商业收入+75%", "农业建筑建造成本-15%"], ["改革: 围棋", "茶叶资源"]),
]
for i, (zh, en, cost, tm, up, fx, req) in enumerate(inn):
    tier_map = {"驿站": 1, "邮驿": 2, "客舍": 3, "客栈": 4, "豪华客栈": 5, "茶室": 3, "茶馆": 4, "大型茶馆": 5}
    tier = tier_map.get(zh, i+1)
    up_from = None
    if zh == "邮驿": up_from = "驿站"
    if zh in ("客舍", "茶室"): up_from = "邮驿"
    if zh == "客栈": up_from = "客舍"
    if zh == "豪华客栈": up_from = "客栈"
    if zh == "茶馆": up_from = "茶室"
    if zh == "大型茶馆": up_from = "茶馆"
    bld(zh, en, "income", tier, up_from, [], cost, tm, up, fx, req, "all",
        "市肆(Inn)链：商业收入；3级分客栈/茶馆两路，茶路需茶叶资源")

# ============================================================
# 10. 学校 Schools
# ============================================================
sch = [
    ("庠序", "County School", 900, 1, 10, ["派系人物经验+4%", "公共秩序+1", "农业建筑建造成本-10%"], ["解锁改革: 塾师(Private Tutors)"]),
    ("学校", "County Academy", 1400, 2, 20, ["派系人物经验+8%", "公共秩序+2", "改革度+4"], []),
    ("郡国学", "Academy", 1900, 2, 30, ["派系人物经验+12%", "公共秩序+3", "改革度+6"], ["需要小区域性城市"]),
    ("精庐", "Academy Complex", 2400, 3, 40, ["派系人物经验+16%", "公共秩序+4", "改革度+10"], ["改革: 察举(Recommendation System)"]),
    ("大型郡国学", "Grand Academy", 2900, 3, 50, ["派系人物经验+20%", "公共秩序+5", "改革度+14"], ["改革: 士行典则(Standards of Scholar Conduct)"]),
]
for i, (zh, en, cost, tm, up, fx, req) in enumerate(sch):
    bld(zh, en, "research", i+1, None if i == 0 else sch[i-1][0],
        None if i == len(sch)-1 else sch[i+1][0], cost, tm, up, fx, req, "all",
        "学校(Schools)链：提升派系人物经验，解锁一半蓝色改革")

# ============================================================
# 11. 市集 Marketplace (主城)
# ============================================================
mk = [
    ("市集", "Shopkeeper", 900, 1, 0, ["商业收入+50%", "贸易影响力+10%(派系)", "农业建筑建造成本-10%"], []),
    ("大市集", "Marketplace", 1400, 1, 0, ["商业收入+75%", "贸易影响力+20%(派系)"], []),
    ("商会", "Merchant Registry Office", 1900, 1, 0, ["商业收入+100%", "贸易影响力+30%(派系)", "公共秩序-8", "改革度+3"], []),
    ("货栈", "Merchant Warehouses", 2400, 1, 0, ["商业收入+125%", "贸易影响力+40%(派系)", "公共秩序-12", "改革度+5", "解锁巨贾"], ["改革: 市令(Market Administration)"]),
    ("商行", "Bureau of Trading Associations", 2900, 1, 0, ["商业收入+150%", "贸易影响力+50%(派系)", "公共秩序-16", "改革度+8", "农业建筑建造成本-15%"], ["改革: 鼓励商贾"]),
    ("丝路远征商铺", "Silk Expedition Trading Post", 2600, 1, 0, ["商业收入+110%", "贸易影响力+35%(派系)", "丝绸收入+15%(派系)"], ["丝绸资源"]),
    ("鼓钟楼", "Drum & Bell Tower", 3200, 1, 0, ["商业收入+150%", "贸易影响力+30%(派系)", "公共秩序-16", "敌方间谍成本+4(派系)", "改革度+6"], ["改革: 市令"]),
]
for i, (zh, en, cost, tm, up, fx, req) in enumerate(mk):
    tier_map = {"市集": 1, "大市集": 2, "商会": 3, "货栈": 4, "商行": 5, "丝路远征商铺": 4, "鼓钟楼": 5}
    tier = tier_map.get(zh, i+1)
    up_from = None
    if zh == "大市集": up_from = "市集"
    if zh == "商会": up_from = "大市集"
    if zh in ("货栈", "丝路远征商铺"): up_from = "商会"
    if zh == "商行": up_from = "货栈"
    if zh == "鼓钟楼": up_from = "商会"
    bld(zh, en, "income", tier, up_from, [], cost, tm, up, fx, req, "all",
        "市集(Marketplace)链：内陆城市商业核心，提升商业收入与贸易影响力")

# ============================================================
# 12. 市场码头 Market Wharf (港口城市替代市集)
# ============================================================
mw = [
    ("港口商铺", "Market Stall", 900, 1, 0, ["商业收入+40", "商业收入+10%", "农业建筑建造成本-10%"], ["靠水城市"]),
    ("港口市集", "Market Square", 1400, 1, 0, ["商业收入+70", "商业收入+20%"], []),
    ("港口货舱", "Market Wharf", 1900, 1, 0, ["商业收入+100", "商业收入+30%"], []),
    ("港口货栈", "Customs House", 2400, 1, 0, ["商业收入+130", "商业收入+40%", "解锁巨贾"], ["改革: 市令(Market Administration)"]),
    ("港口商行", "Trade Company", 2900, 1, 0, ["商业收入+160", "商业收入+50%", "贸易影响力+15%(派系)"], ["改革: 鼓励商贾"]),
    ("巡官署", "Harbour Inspectorate", 2400, 1, 0, ["商业收入+130", "商业收入+40%", "敌方间谍成本+2(派系)"], ["改革: 伪装诡道(Disguise Deceptions)"]),
    ("港监署", "Harbour Command", 2900, 1, 0, ["商业收入+160", "商业收入+50%", "敌方间谍成本+4(派系)"], ["改革: 用间(Use of Spies)"]),
]
for i, (zh, en, cost, tm, up, fx, req) in enumerate(mw):
    tier_map = {"港口商铺": 1, "港口市集": 2, "港口货舱": 3, "港口货栈": 4, "港口商行": 5, "巡官署": 4, "港监署": 5}
    tier = tier_map.get(zh, i+1)
    up_from = None
    if zh == "港口市集": up_from = "港口商铺"
    if zh == "港口货舱": up_from = "港口市集"
    if zh in ("港口货栈", "巡官署"): up_from = "港口货舱"
    if zh == "港口商行": up_from = "港口货栈"
    if zh == "港监署": up_from = "巡官署"
    bld(zh, en, "income", tier, up_from, [], cost, tm, up, fx, req, "all",
        "市场码头(Market Wharf)链：港口城市的市集替代链")

# ============================================================
# 13. 征募 Conscription
# ============================================================
cs = [
    ("募兵所", "Conscription Office", 1000, 1, 0, ["新征部队初始等级+2(本地)", "政府建筑建造成本-10%", "人口增长-4K"], []),
    ("治兵场", "Training Field", 2000, 1, 0, ["新征部队初始等级+2", "派系每季部曲部署+1", "人口增长-6K"], []),
    ("讲武营", "Training Camp", 3000, 1, 0, ["新征部队初始等级+3", "派系每季部曲部署+2", "重新部署费用-5%(派系)", "人口增长-8K"], ["改革: 征召卫兵(Garrison Conscripts)"]),
]
for i, (zh, en, cost, tm, up, fx, req) in enumerate(cs):
    bld(zh, en, "military", i+1, None if i == 0 else cs[i-1][0],
        None if i == len(cs)-1 else cs[i+1][0], cost, tm, up, fx, req, "all",
        "征募(Conscription)链：新兵经验加成，减少人口增长")

# ============================================================
# 14. 兵工 Military Forges
# ============================================================
mf = [
    ("铁匠铺", "Blacksmith", 1750, 1, 30, ["招募费用-10%(本地)", "工业收入+10%", "政府建筑建造成本-10%"], []),
    ("铸兵室", "Military Forge", 2100, 1, 40, ["招募费用-10%(本地)", "工业收入+20%"], ["改革: 郡国铸兵室(Provincial Military Forges)"]),
    ("铸甲所", "Military Armourer", 2400, 2, 40, ["近战步兵招募费用-10%", "产出甲胄(至精良品质)"], ["改革: 青龙舰(Green Dragon Ships)", "手工业者", "铁矿"]),
    ("制弓所", "Military Bow-Makers", 2400, 2, 40, ["远程部队招募费用-10%", "产出弓弩(至精良品质)"], ["改革: 青龙舰", "匠师", "铁矿"]),
    ("冶兵所", "Military Weaponsmith", 2400, 2, 40, ["矛兵招募费用-10%", "产出兵器(至精良品质)"], ["改革: 青龙舰", "手工业者", "铁矿"]),
]
for i, (zh, en, cost, tm, up, fx, req) in enumerate(mf):
    tier_map = {"铁匠铺": 1, "铸兵室": 2, "铸甲所": 3, "制弓所": 3, "冶兵所": 3}
    tier = tier_map.get(zh, i+1)
    up_from = None
    if zh == "铸兵室": up_from = "铁匠铺"
    if zh in ("铸甲所", "制弓所", "冶兵所"): up_from = "铸兵室"
    bld(zh, en, "military", tier, up_from, [], cost, tm, up, fx, req, "all",
        "兵工(Military Forges)链：降低招募费用并产出武器/甲胄/弓弩饰品")

# ============================================================
# 15. 军武设施 Military Infrastructure
# ============================================================
mi = [
    ("巡守营", "Patrols", 1200, 1, 20, ["公共秩序+2", "军事补给+5(相邻郡国)", "政府建筑建造成本-10%"], ["解锁改革: 畜牧许可(Livestock Licences)"]),
    ("卫戍岗", "Guards Posts", 2000, 1, 20, ["公共秩序+4", "军事补给+10(相邻)"], []),
    ("武卫营", "Stationed Garrison", 2700, 2, 30, ["公共秩序+8", "军事补给+12", "粮食储备+20"], []),
    ("中垒营", "Police Headquarters", 4000, 2, 30, ["公共秩序+10", "军事补给+20", "粮食储备+40"], ["改革: 运漕(Transport by Canal)"]),
    ("宿卫军营", "Fortified Garrison", 5500, 3, 40, ["军事补给+30", "粮食储备+60", "政府建筑建造成本-15%"], ["改革: 要塞(Fortresses)"]),
    ("巡守军营", "Patrol Barracks", 1800, 1, 20, ["公共秩序+6", "军事补给+15", "敌方军事补给-5"], []),
    ("哨楼戍卫", "Watchtower Garrisons", 2200, 2, 30, ["军事补给+25"], ["改革: 运漕"]),
    ("战略要塞", "Strategic Fortress", 3100, 3, 40, ["军事补给+40", "敌方军事补给-10", "政府建筑建造成本-15%"], ["改革: 要塞"]),
    ("白马义从团", "White Horse Fellows Riding Parties", 4100, 3, 40, ["骑兵新征初始等级+1(本地)", "军事补给+40", "敌方军事补给-20"], ["改革: 兵贵神速", "育马资源"]),
]
for i, (zh, en, cost, tm, up, fx, req) in enumerate(mi):
    tier_map = {"巡守营": 1, "卫戍岗": 2, "武卫营": 3, "中垒营": 4, "宿卫军营": 5, "巡守军营": 3, "哨楼戍卫": 4, "战略要塞": 5, "白马义从团": 5}
    tier = tier_map.get(zh, i+1)
    up_from = None
    if zh == "卫戍岗": up_from = "巡守营"
    if zh in ("武卫营", "巡守军营"): up_from = "卫戍岗"
    if zh == "中垒营": up_from = "武卫营"
    if zh == "宿卫军营": up_from = "中垒营"
    if zh == "哨楼戍卫": up_from = "巡守军营"
    if zh in ("战略要塞", "白马义从团"): up_from = "哨楼戍卫"
    bld(zh, en, "military", tier, up_from, [], cost, tm, up, fx, req, "all",
        "军武设施(Military Infrastructure)链：军事补给、驻军与公共秩序")

# ============================================================
# 16. 公府 Administration Office
# ============================================================
ao = [
    ("县令府", "County Office", 1000, 1, 0, ["全部收入+10%", "声望+5", "经济建筑建造成本-10%"], []),
    ("掾史府", "Magistrate", 2000, 3, 0, ["全部收入+15%", "声望+10"], []),
    ("郡府主薄", "Secretariat of the Commandery", 3000, 3, 0, ["全部收入+20%", "声望+15"], []),
    ("郡府", "Directorate of the Commandery", 4000, 4, 0, ["全部收入+25%", "声望+20"], ["改革: 中常侍(Regular Palace Attendants)"]),
    ("宫殿", "Imperial Palace", 12000, 10, 0, ["农民收入+500", "声望+30", "精英禁卫军驻军", "经济建筑建造成本-50%", "全部收入+10%(替代百分比加成)"], ["改革: 受命于天(Mandate of Heaven)", "每派系仅一座"]),
    ("县丞府", "Court", 3000, 3, 0, ["本地腐败-10%"], ["改革: 黄门宦官(Eunuch Secretaries)"]),
    ("决曹", "Judiciary", 4000, 4, 0, ["本地腐败-15%"], ["改革: 中常侍"]),
    ("郡决曹", "Grand Judiciary", 5000, 4, 0, ["本地腐败-20%"], ["改革: 六部(Six Bureaus of Bureaucracy)"]),
    ("御史府", "Office for Archives and Seals", 5500, 4, 0, ["相邻郡国腐败-20%"], ["改革: 六部", "玉石资源", "匠师资源", "需要7级城市"]),
]
for i, (zh, en, cost, tm, up, fx, req) in enumerate(ao):
    tier_map = {"县令府": 1, "掾史府": 2, "郡府主薄": 3, "郡府": 4, "宫殿": 5, "县丞府": 3, "决曹": 4, "郡决曹": 5, "御史府": 5}
    tier = tier_map.get(zh, i+1)
    up_from = None
    if zh == "掾史府": up_from = "县令府"
    if zh in ("郡府主薄", "县丞府"): up_from = "掾史府"
    if zh == "郡府": up_from = "郡府主薄"
    if zh == "宫殿": up_from = "郡府"
    if zh == "决曹": up_from = "县丞府"
    if zh in ("郡决曹", "御史府"): up_from = "决曹"
    bld(zh, en, "public_order", tier, up_from, [], cost, tm, up, fx, req, "all",
        "公府(Administration Office)链：全收入加成与反腐；3级分主薄(收入)/县丞(反腐)两路")

# ============================================================
# 17. 孔庙 Confucian Temples
# ============================================================
ct = [
    ("孔祠", "Confucian Shrine", 900, 1, 10, ["公共秩序+4", "经济建筑建造成本-10%", "宗教热情-5", "全部收入+5%"], []),
    ("孔庙", "Confucian Temple", 1400, 1, 20, ["公共秩序+8", "经济建筑建造成本-10%", "宗教热情-10", "全部收入+10%"], ["解锁改革: 祫祀禘祭(Mastery of Ceremonies)"]),
    ("大型孔庙", "Grand Temple of Confucius", 2700, 2, 50, ["公共秩序+16", "经济建筑建造成本-10%", "宗教热情-15", "全部收入+15%"], ["改革: 无为而治(Principles of Wu Wei)"]),
]
for i, (zh, en, cost, tm, up, fx, req) in enumerate(ct):
    bld(zh, en, "public_order", i+1, None if i == 0 else ct[i-1][0],
        None if i == len(ct)-1 else ct[i+1][0], cost, tm, up, fx, req, "all",
        "孔庙(Confucian Temples)链：公共秩序核心建筑")

# ============================================================
# 18. 税收 Tax Collection
# ============================================================
tx = [
    ("啬夫署", "Rural Tax Collectors", 0, 1, 0, ["农民收入+80", "公共秩序-4", "经济建筑建造成本-10%"], ["解锁改革: 贼曹(Bureau of Banditry)"]),
    ("乡政署", "Rural Administration Office", 0, 1, 0, ["农民收入+110", "公共秩序-8"], []),
    ("县辖乡政署", "Rural County Administration", 0, 1, 0, ["农民收入+140", "公共秩序-12"], ["改革: 贼曹"]),
    ("郡辖乡政署", "Rural Commandery Administration", 0, 1, 0, ["农民收入+200", "公共秩序-16"], ["改革: 具五刑(The Five Punishments)"]),
    ("州辖乡政署", "Rural Province Administration", 0, 1, 0, ["农民收入+240", "公共秩序-20", "经济建筑建造成本-15%"], ["改革: 均输官(Commissioners of Passage)"]),
]
for i, (zh, en, cost, tm, up, fx, req) in enumerate(tx):
    bld(zh, en, "income", i+1, None if i == 0 else tx[i-1][0],
        None if i == len(tx)-1 else tx[i+1][0], cost, tm, up, fx, req, "all",
        "税收(Tax Collection)链：免费建造，提升农民收入但降低公共秩序")

# ============================================================
# 19-30. 资源建筑 Resource Settlements
# ============================================================
res_buildings = [
    # (链名, 资源, 建筑列表 [(name_zh, name_en, cost, effects, req), ...])
    ("农田/农庄", "谷物", [
        ("农田", "Farmland", 800, ["粮食+2", "农民收入+80", "军事建筑建造成本-10%", "提供谷物资源"], []),
        ("农庄", "Farmland Estates", 1200, ["粮食+4", "农民收入+100", "提供谷物资源"], []),
        ("公家农庄", "State Farmland", 1800, ["粮食+6", "农民收入+120", "提供谷物资源"], []),
        ("田庄", "Manor", 2600, ["粮食+8", "农民收入+140", "提供谷物资源"], ["改革: 省禁轻租(Moderate Taxes)"]),
        ("大型田庄", "Grand Manor", 3600, ["粮食+10", "农民收入+160", "声望+15", "军事建筑建造成本-15%", "提供谷物资源"], ["改革: 地主豪族(Landlord Magnates)"]),
    ]),
    ("铁矿", "铁矿", [
        ("铁矿坑", "Open Iron Veins", 1500, ["工业收入+100", "声望+5", "粮食储备+10", "政府建筑建造成本-10%", "提供铁矿"], ["解锁改革: 辘轳采矿(Shaft Mining)"]),
        ("铁矿矿坑", "Iron Pits", 2600, ["工业收入+200", "提供铁矿"], []),
        ("铁矿山", "Iron Mine", 3700, ["工业收入+300", "提供铁矿"], []),
        ("铁艺村庄", "Iron Craftwork Village", 4800, ["工业收入+400", "声望+10", "提供铁矿"], ["改革: 辘轳采矿", "匠师资源"]),
        ("铁艺城镇", "Iron Craftwork Town", 6400, ["工业收入+500", "声望+15", "政府建筑建造成本-15%", "提供铁矿"], ["改革: 排气室(Ventilation Shafts)", "匠师资源"]),
        ("军备村庄", "Military Supply Village", 4800, ["军事补给+10(相邻)", "工业收入+200", "提供铁矿"], ["改革: 郡国兵器室(County Armouries)", "手工业者"]),
        ("军备城镇", "Military Supply Town", 6400, ["军事补给+20(相邻)", "工业收入+300", "提供铁矿"], ["改革: 青龙舰(Green Dragon Ships)", "手工业者"]),
    ]),
    ("食盐", "食盐", [
        ("盐泉", "Brine Spring", 1500, ["工业收入+100", "声望+5", "粮食储备+10", "农业建筑建造成本-10%", "提供食盐"], ["解锁改革: 辘轳采矿"]),
        ("盐池", "Salt Ponds", 2600, ["工业收入+200", "提供食盐"], []),
        ("盐田", "Salt Works", 3700, ["工业收入+300", "提供食盐"], []),
        ("盐矿", "Salt Shaft Mine", 4800, ["工业收入+400", "声望+10", "提供食盐"], ["改革: 市令(Market Administration)"]),
        ("盐矿城镇", "Salt Mining Town", 6400, ["工业收入+550", "声望+15", "农业建筑建造成本-15%", "提供食盐"], ["改革: 鼓励商贾(Encourage Merchants)", "手工业者"]),
    ]),
    ("玉石", "玉石", [
        ("采玉工房", "Jade Collectors", 1200, ["工业收入+90", "商业收入+60", "声望+5", "粮食储备+10", "提供玉石"], []),
        ("玉矿床", "Jade Deposits", 2000, ["工业收入+130", "商业收入+90", "提供玉石"], []),
        ("琢玉坊", "Jade Workshop", 2800, ["工业收入+170", "商业收入+120", "提供玉石"], []),
        ("玉雕匠坊", "Jade Master Artisans", 3600, ["工业收入+225", "商业收入+150", "声望+10", "提供玉石"], ["改革: 辘轳采矿", "匠师资源"]),
        ("宝玉工室", "Jade Treasure Works", 4400, ["工业收入+280", "商业收入+180", "声望+15", "提供玉石"], ["改革: 排气室", "匠师资源"]),
        ("玉石贸易村", "Jade Trading Village", 3600, ["商业收入+150", "贸易影响力+10%(派系)", "声望+10", "提供玉石"], ["改革: 市令", "巨贾资源"]),
        ("玉石贸易镇", "Jade Trading Town", 4400, ["商业收入+200", "贸易影响力+15%(派系)", "声望+15", "提供玉石"], ["改革: 鼓励商贾", "巨贾资源"]),
    ]),
    ("松木", "木材", [
        ("松木场", "Pine Lumber Yard", 800, ["农民收入+40", "声望+5", "粮食储备+10", "军事建筑建造成本-10%", "提供木材"], []),
        ("松林伐木场", "Pine Woodcutter", 1150, ["农民收入+70", "提供木材"], []),
        ("松林伐木营地", "Pine Woodcutter Camp", 1450, ["农民收入+100", "提供木材"], []),
        ("松木置所", "Pine Timber Storehouse", 1800, ["农民收入+130", "声望+10", "提供木材"], ["改革: 赋与佃器(Government Tool Distribution)"]),
        ("松木贸易营地", "Pine Trader Camp", 2450, ["农民收入+160", "声望+15", "贸易影响力+15%(派系)", "军事建筑建造成本-15%", "提供木材"], ["改革: 租佃制度", "巨贾"]),
        ("木器营地", "Composite Wood Maker Camp", 2400, ["农民收入+150", "军事补给+5(本地)", "提供木材"], ["改革: 租佃制度", "匠师"]),
    ]),
    ("竹木", "木材", [
        ("竹木场", "Bamboo Lumber Yard", 800, ["农民收入+40", "声望+5", "粮食储备+10", "军事建筑建造成本-10%", "提供木材"], []),
        ("竹林伐木场", "Bamboo Woodcutter", 1150, ["农民收入+70", "提供木材"], []),
        ("竹林伐木营地", "Bamboo Woodcutter Camp", 1450, ["农民收入+100", "提供木材"], []),
        ("竹木置所", "Bamboo Timber Storehouse", 1800, ["农民收入+130", "声望+10", "提供木材"], ["改革: 赋与佃器"]),
        ("竹木仓库", "Bamboo Timber Warehouse", 2400, ["农民收入+150", "声望+15", "军事建筑建造成本-15%", "提供木材"], ["改革: 租佃制度", "手工业者"]),
    ]),
    ("丝绸", "丝绸", [
        ("丝路商铺", "Silk Road Trader", 1250, ["丝绸收入+75", "派系丝绸收入+15%", "声望+5", "粮食储备+10", "农业建筑建造成本-10%", "提供丝绸"], []),
        ("丝路商馆", "Silk Road Trading Post", 1850, ["丝绸收入+125", "派系丝绸收入+25%", "提供丝绸"], []),
        ("丝路馆驿", "Silk Road Caravan Post", 2450, ["丝绸收入+175", "派系丝绸收入+40%", "提供丝绸"], []),
        ("丝路市集", "Silk Road Market", 3050, ["丝绸收入+225", "派系丝绸收入+50%", "声望+10", "提供丝绸"], ["改革: 使节团(Diplomatic Missions)"]),
        ("大型丝路市集", "Grand Silk Road Market", 3450, ["丝绸收入+250", "派系丝绸收入+65%", "声望+15", "农业建筑建造成本-15%", "提供丝绸"], ["改革: 丝路远行(Silk Road Journeys)", "巨贾资源"]),
    ]),
    ("茶叶", "茶叶", [
        ("茶场", "Tea Plants", 1100, ["商业收入+70", "声望+5", "粮食储备+10", "军事建筑建造成本-10%", "提供茶叶"], []),
        ("种茶园", "Tea Grower", 1700, ["商业收入+100", "提供茶叶"], []),
        ("公家茶庄", "Tea Grower Community", 2300, ["商业收入+130", "提供茶叶"], []),
        ("茶圃", "Tea Plantation", 2900, ["商业收入+160", "声望+10", "提供茶叶"], ["改革: 农书(Treatise on Agriculture)"]),
        ("大茶圃", "Grand Tea Plantation", 3600, ["商业收入+200", "声望+15", "军事建筑建造成本-15%", "提供茶叶"], ["改革: 密植(Intensive Planting)"]),
        ("茶苑", "Tea Garden", 2900, ["商业收入+150", "贸易影响力+10%(派系)", "提供茶叶"], ["改革: 农书", "巨贾资源"]),
        ("大茶苑", "Grand Tea Garden", 3600, ["商业收入+180", "贸易影响力+15%(派系)", "提供茶叶"], ["改革: 密植", "巨贾资源"]),
    ]),
    ("铜矿", "铜矿", [
        ("铜矿脉", "Copper Vein", 1500, ["工业收入+100", "声望+5", "粮食储备+10", "学习与市场建筑建造成本-10%", "提供铜矿"], []),
        ("铜矿坑", "Copper Pits", 2600, ["工业收入+200", "提供铜矿"], []),
        ("铜矿山", "Copper Mine", 3700, ["工业收入+300", "提供铜矿"], []),
        ("铜矿村庄", "Copper Mining Village", 4800, ["工业收入+400", "声望+10", "提供铜矿"], ["改革: 辘轳采矿"]),
        ("铜矿城镇", "Copper Mining Town", 6400, ["工业收入+500", "声望+15", "学习与市场建筑建造成本-15%", "提供铜矿"], ["改革: 排气室", "手工业者"]),
        ("铜矿铸造厂", "Copper Coin Mint", 6400, ["工业收入+500", "派系腐败-4%(每座，至多-24%)", "提供铜矿"], ["改革: 铸币(Minting Coins)", "匠师资源"]),
    ]),
    ("牧场", "畜牧", [
        ("牧场", "Livestock Farm", 900, ["粮食+2", "农民收入+120", "声望+5", "提供畜牧资源"], ["解锁资源: 畜牧"]),
        ("畜栏", "Livestock Enclosures", 1400, ["粮食+3", "农民收入+140", "提供畜牧资源"], []),
        ("畜牧场", "Livestock Ranch", 2000, ["粮食+4", "农民收入+160", "提供畜牧资源"], []),
        ("畜牧田庄", "Livestock Estate", 2800, ["粮食+5", "农民收入+180", "声望+10", "提供畜牧资源"], ["改革: 鼓励占垦(Encouraging Settlement)"]),
        ("大型畜牧田庄", "Grand Livestock Estate", 3600, ["粮食+6", "农民收入+250", "声望+15", "提供畜牧资源"], ["改革: 地主豪族"]),
        ("畜牧农庄", "Livestock Farmstead", 3600, ["粮食+10", "农民收入+180", "声望+15", "提供畜牧资源"], ["改革: 地主豪族"]),
    ]),
    ("渔业", "渔业", [
        ("渔村", "Fishing Village", 1000, ["粮食+2(渔业)", "商业收入+50", "声望+5", "提供渔业资源"], []),
        ("公用渔湾", "Public Fishing Cove", 1600, ["粮食+3(渔业)", "商业收入+80", "提供渔业资源"], []),
        ("公用渔港", "Public Fishing Harbour", 2200, ["粮食+4(渔业)", "商业收入+110", "提供渔业资源"], []),
        ("渔舟泊港", "Fishing Fleet Port", 2900, ["粮食+5(渔业)", "商业收入+140", "声望+10", "提供渔业资源"], ["改革: 横隔舱(Bulkhead Compartments)"]),
        ("大型渔港码头", "Grand Fishing Port", 3600, ["粮食+6(渔业)", "商业收入+170", "声望+15", "提供渔业资源"], ["改革: 平底船(Flat-bottomed Boats)"]),
        ("捕鱼船坞", "Fishing Shipyard", 3600, ["粮食+5(渔业)", "商业收入+200", "声望+15", "提供渔业资源"], ["改革: 平底船", "木材资源"]),
    ]),
    ("商港(滨海)", "无(贸易)", [
        ("滨海商埠", "Coastal Trade Post", 1200, ["商业收入+60", "声望+5", "提供贸易"], []),
        ("滨海商贸驿站", "Coastal Trading Station", 1900, ["商业收入+100", "提供贸易"], []),
        ("滨海商港", "Coastal Trade Harbour", 2600, ["商业收入+140", "提供贸易"], []),
        ("滨海商贸村庄", "Coastal Trading Village", 3400, ["商业收入+180", "声望+10", "提供贸易"], ["改革: 外邦使者(Foreign Envoys)"]),
        ("滨海商贸城镇", "Coastal Trading Town", 4200, ["商业收入+230", "声望+15", "贸易影响力+15%(派系)", "提供贸易"], ["改革: 丝路远行", "巨贾资源"]),
        ("工商口岸", "Industrial Trading Port", 4200, ["商业收入+230", "工业收入+100", "声望+15", "提供贸易"], ["改革: 丝路远行", "手工业者"]),
        ("香药商港城市", "Spice Trading Port City", 4600, ["商业收入+250", "派系香药收入+15%", "声望+15", "提供贸易"], ["改革: 丝路远行", "巨贾资源", "香药资源"]),
    ]),
    ("工具", "工具", [
        ("工具铸所", "Tool Foundry", 1000, ["农民收入+40", "工业收入+40", "声望+5", "提供工具资源"], []),
        ("工具工坊", "Tool Workshop", 1500, ["农民收入+70", "工业收入+70", "提供工具资源"], []),
        ("工具库", "Tool Warehouse", 2000, ["农民收入+100", "工业收入+100", "提供工具资源"], []),
        ("匠器库", "Crafting Tool Warehouse", 2700, ["农民收入+130", "工业收入+130", "声望+10", "提供工具资源"], ["改革: 官营作业(State Works)", "匠师资源"]),
        ("匠器工室", "Crafting Tool Works", 3400, ["农民收入+160", "工业收入+160", "声望+15", "提供工具资源"], ["改革: 庄田典册(Land Registers)", "匠师资源"]),
        ("工器库", "Industrial Tool Warehouse", 2700, ["农民收入+130", "工业收入+130", "声望+10", "提供工具资源"], ["改革: 官营作业", "手工业者资源"]),
        ("工器工室", "Industrial Tool Works", 3400, ["农民收入+160", "工业收入+160", "声望+15", "提供工具资源"], ["改革: 庄田典册", "手工业者资源"]),
    ]),
    ("铸甲", "无(匠师)", [
        ("知名铸甲所", "Famous Armourer", 2000, ["产出甲胄(至精良品质)", "声望+5"], []),
        ("驰名铸甲所", "Renowned Armourer", 3000, ["产出甲胄(至精良品质)", "声望+10"], []),
        ("传奇铸甲所", "Legendary Armourer", 4200, ["产出甲胄(至精良品质)", "声望+15"], ["匠师资源"]),
    ]),
]
for chain_zh, res, items in res_buildings:
    prev = None
    for idx, (zh, en, cost, fx, req) in enumerate(items):
        bld(zh, en, "income", idx+1, prev, [] if idx == len(items)-1 else [items[idx+1][0]],
            cost, 2 if idx >= 3 else 1, 0, fx, req, "all",
            "%s资源建筑链(需对应资源)：%s" % (chain_zh, res))
        prev = zh

# ============================================================
# 31. 派系特殊建筑 Faction Unique Buildings
# ============================================================
faction_blds = [
    # 曹操 - 屯田 (Tuntian)
    ("募兵府", "Conscription Bureau (Cao Cao)", "military", [
        ["军事建筑建造成本-10%", "新征部队初始等级+2"], []],
     "曹操(Cao Cao)"),
    ("兵户治兵场", "Soldier Household Training Field", "military", [["新征部队初始等级+2", "派系每季部曲部署+1"], []], "曹操"),
    ("兵户讲武营", "Soldier Household Training Camp", "military", [["新征部队初始等级+3", "派系每季部曲部署+2"], []], "曹操"),
    ("兵户军营", "Soldier Household Barracks", "military", [["新征部队初始等级+3", "派系每季部曲部署+2", "粮食产量+10%"], ["改革: 家兵(Retainer Armies)", "谷物资源"]], "曹操"),
    ("军屯署", "Tuntian Headquarters", "military", [["新征部队初始等级+3", "派系每季部曲部署+2", "粮食产量+20%", "战役移动范围+5%"], ["改革: 世袭部曲(Hereditary Retinues)", "谷物资源"]], "曹操"),
    ("__CHAIN__", "sentinel", "x", [[], []], "x"),
    ("军屯田", "Tuntian Fields", "food", [["粮食+2", "农民收入+60", "提供谷物资源"], []], "曹操"),
    ("军屯营地", "Tuntian Camp", "food", [["粮食+4", "农民收入+90", "提供谷物资源"], []], "曹操"),
    ("军屯兵营", "Tuntian Barracks", "food", [["粮食+6", "农民收入+120", "提供谷物资源"], []], "曹操"),
    ("军屯驻地", "Tuntian Garrison", "food", [["粮食+8", "农民收入+150", "军事补给+10", "提供谷物资源"], ["改革: 平准仓(Ever-level Granaries)"]], "曹操"),
    ("军屯堡垒", "Tuntian Fortress", "food", [["粮食+10", "农民收入+200", "军事补给+20", "提供谷物资源"], ["改革: 军屯(Military Colonies)"]], "曹操"),
    # 刘备 - 蜀汉税收
    ("蜀汉啬夫署", "Tax Collector Office of Han Empire", "income", [["农民收入+85", "公共秩序无惩罚", "民兵补给+3%", "经济建筑建造成本-10%"], ["解锁改革: 贼曹"]], "刘备(Liu Bei)"),
    ("蜀汉乡政署", "Village Administration of Han Empire", "income", [["农民收入+120", "公共秩序无惩罚", "民兵补给+6%"], []], "刘备"),
    ("蜀汉县政署", "County Administration of Han Empire", "income", [["农民收入+150", "公共秩序无惩罚", "民兵补给+9%"], ["改革: 贼曹"]], "刘备"),
    ("蜀汉郡政署", "Commandery Administration of Han Empire", "income", [["农民收入+210", "公共秩序无惩罚", "民兵补给+12%"], ["改革: 具五刑"]], "刘备"),
    ("蜀汉州政署", "Province Administration of Han Empire", "income", [["农民收入+260", "公共秩序无惩罚", "民兵补给+15%", "经济建筑建造成本-15%"], ["改革: 均输官"]], "刘备"),
    # 孙坚 - 佣兵
    ("__CHAIN__", "sentinel", "x", [[], []], "x"),
    ("商旅卫所", "Trade Escort Station", "military", [["佣兵补给+5%"], []], "孙坚(Sun Jian)"),
    ("商旅护卫营", "Trade Escort Camp", "military", [["佣兵补给+10%"], []], "孙坚"),
    ("佣兵征募署", "Mercenary Recruiting Office", "military", [["佣兵补给+15%", "佣兵招募费用-5%"], []], "孙坚"),
    ("佣兵营地", "Mercenary Camp", "military", [["佣兵补给+25%", "佣兵招募费用-10%"], ["改革: 整顿商贾", "巨贾资源"]], "孙坚"),
    ("佣兵大营", "Grand Mercenary Camp", "military", [["佣兵补给+40%", "佣兵招募费用-15%"], ["改革: 行肆市列", "巨贾资源"]], "孙坚"),
    # 公孙瓒 - 军武府
    ("督邮府", "Inspector Office", "government", [["全部收入+5%", "公共秩序+2"], []], "公孙瓒(Gongsun Zan)"),
    ("县尉府", "County Defender Office", "government", [["全部收入+10%", "公共秩序+4"], []], "公孙瓒"),
    ("郡尉府", "Commandery Defender Office", "government", [["全部收入+15%", "公共秩序+6"], []], "公孙瓒"),
    ("白马尉营", "White Horse Captain Camp", "government", [["全部收入+20%", "骑兵新征等级+1"], ["改革: 家兵"]], "公孙瓒"),
    ("白马尉堂", "White Horse Captain Hall", "government", [["全部收入+30%", "骑兵新征等级+2"], ["改革: 世袭部曲"]], "公孙瓒"),
    ("__CHAIN__", "sentinel", "x", [[], []], "x"),
    ("郡卫营地", "Commandery Guard Camp", "government", [["全部收入+20%", "本地腐败-10%"], ["改革: 家兵"]], "公孙瓒"),
    ("军令府", "Military Command", "government", [["全部收入+30%", "本地腐败-20%"], ["改革: 世袭部曲"]], "公孙瓒"),
    # 袁绍 - 袁氏府署
    ("袁氏官府", "Yuan County Office", "government", [["全部收入+10%", "声望+5"], []], "袁绍(Yuan Shao)"),
    ("袁氏掾史府", "Yuan Magistrate", "government", [["全部收入+20%", "声望+10"], []], "袁绍"),
    ("袁氏主薄府", "Yuan Secretariat", "government", [["全部收入+30%", "声望+15"], []], "袁绍"),
    ("袁氏郡府", "Yuan Directorate", "government", [["全部收入+40%", "声望+20"], ["改革: 中常侍"]], "袁绍"),
    ("袁氏宫殿", "Palace of Yuan", "government", [["全部收入+50%", "声望+30", "经济建筑建造成本-15%", "每派系仅一座"], ["改革: 受命于天"]], "袁绍"),
    # 袁术 - 仲家公府
    ("仲家县令府", "Zhong County Office", "government", [["全部收入+10%", "声望+5"], []], "袁术(Yuan Shu)"),
    ("仲家掾史府", "Zhong Magistrate", "government", [["全部收入+15%", "声望+10"], []], "袁术"),
    ("仲家主薄府", "Zhong Secretariat", "government", [["全部收入+20%", "声望+15"], []], "袁术"),
    ("仲家郡府", "Zhong Directorate", "government", [["全部收入+25%", "声望+20"], ["改革: 中常侍"]], "袁术"),
    ("仲家宫殿", "Zhong Palace", "government", [["全部收入+30%", "声望+30", "经济建筑建造成本-50%", "每派系仅一座"], ["改革: 受命于天"]], "袁术"),
    # 孔融 - 学府
    ("公塾", "Public Teachers", "research", [["人口增长+4K", "公共秩序+2", "农业建筑建造成本-10%"], ["改革: 塾师"]], "孔融(Kong Rong)"),
    ("公学", "Public School", "research", [["人口增长+12K", "公共秩序+4"], []], "孔融"),
    ("公学馆", "Public Academy", "research", [["人口增长+25K", "公共秩序+6"], []], "孔融"),
    ("精舍", "Academy Complex (Kong Rong)", "research", [["人口增长+50K", "公共秩序+8", "全部收入+15%"], ["改革: 察举"]], "孔融"),
    ("大型公学馆", "Grand Public Academy", "research", [["人口增长+100K", "公共秩序+10", "全部收入+30%", "农业建筑建造成本-15%"], ["改革: 士行典则"]], "孔融"),
    ("__CHAIN__", "sentinel", "x", [[], []], "x"),
    ("诗馆", "Academy of Poetry", "research", [["文化收入+150", "公共秩序+8"], ["改革: 察举"]], "孔融"),
    ("大型诗馆", "Grand Academy of Poetry", "research", [["文化收入+250", "公共秩序+10"], ["改革: 察举"]], "孔融"),
    # 刘表 - 客栈
    ("府史旅舍", "Clerk Travel Lodge", "income", [["治理+1(派系)", "商业收入+120", "商业收入+10%", "农业建筑建造成本-10%"], []], "刘表(Liu Biao)"),
    ("公侯旅舍", "Noble Travel Lodge", "income", [["商业收入+140", "商业收入+25%"], []], "刘表"),
    ("名士客舍", "Gentlemen Lodge", "income", [["治理+2(派系)", "商业收入+160", "商业收入+50%"], []], "刘表"),
    ("名士客栈", "Gentlemen Guest House", "income", [["商业收入+180", "商业收入+80%"], ["改革: 六博"]], "刘表"),
    ("名士豪苑客栈", "Gentlemen Guest House Garden", "income", [["治理+4(派系)", "商业收入+200", "商业收入+120%", "农业建筑建造成本-15%"], ["改革: 围棋"]], "刘表"),
    ("__CHAIN__", "sentinel", "x", [[], []], "x"),
    ("名士茶室", "Gentlemen Tea Parlour", "income", [["治理+3(派系)", "人物经验+5%(派系)", "商业收入+170", "商业收入+40%"], ["茶叶资源"]], "刘表"),
    ("名士茶馆", "Gentlemen Tea House", "income", [["商业收入+210", "商业收入+60%"], ["改革: 六博", "茶叶资源"]], "刘表"),
    ("名士茶苑", "Gentlemen Grand Tea House", "income", [["治理+5(派系)", "商业收入+250", "商业收入+80%"], ["改革: 围棋", "茶叶资源"]], "刘表"),
    # 马腾 - 西凉补给
    ("游骑营", "Roving Cavalry Camp", "military", [["军事补给+5(相邻)", "骑兵新征等级+1"], []], "马腾(Ma Teng)"),
    ("骁骑营", "Valiant Cavalry Camp", "military", [["军事补给+10(相邻)", "骑兵新征等级+1"], []], "马腾"),
    ("巡护骑营", "Patrol Cavalry Camp", "military", [["军事补给+15(相邻)", "骑兵新征等级+2"], []], "马腾"),
    ("巡护骁骑营", "Patrol Valiant Cavalry Camp", "military", [["军事补给+20(相邻)", "骑兵新征等级+2", "公共秩序+4"], ["改革: 家兵"]], "马腾"),
    ("巡护万骑营", "Patrol Myriad Cavalry Camp", "military", [["军事补给+30(相邻)", "骑兵新征等级+3", "公共秩序+8"], ["改革: 突骑横行(Charging Cavalry Tactics)"]], "马腾"),
    # 张燕 - 黑山匪窝
    ("黑山匪窝", "Black Mountain Hideout", "military", [["土匪收入+100", "可对黄巾军进行外交"], []], "张燕(Zhang Yan)"),
    ("黑山贼巢", "Black Mountain Den", "military", [["土匪收入+150", "人口增长+4K"], []], "张燕"),
    ("黑山坞堡", "Black Mountain Fort", "military", [["土匪收入+200", "公共秩序+6"], ["改革: 州牧(Governorships)"]], "张燕"),
    ("黑山大寨", "Black Mountain Stronghold", "military", [["土匪收入+250", "公共秩序+8"], ["改革: 家兵"]], "张燕"),
    ("黑山坚堡", "Black Mountain Bastion", "military", [["土匪收入+350", "公共秩序+12"], ["改革: 世袭部曲"]], "张燕"),
    ("__CHAIN__", "sentinel", "x", [[], []], "x"),
    ("黑山匿所", "Black Mountain Hideaway", "research", [["土匪收入+150", "敌方间谍成本+2"], ["改革: 塾师"]], "张燕"),
    ("黑山避所", "Black Mountain Refuge", "research", [["土匪收入+200", "敌方间谍成本+4"], ["改革: 伪装诡道"]], "张燕"),
    ("黑山护地", "Black Mountain Sanctuary", "research", [["土匪收入+280", "敌方间谍成本+6"], ["改革: 用间"]], "张燕"),
    ("__CHAIN__", "sentinel", "x", [[], []], "x"),
    ("黑山议厅", "Black Mountain Council", "public_order", [["土匪收入+150", "公共秩序+4"], ["改革: 黄门宦官"]], "张燕"),
    ("黑山公堂", "Black Mountain Court", "public_order", [["土匪收入+200", "公共秩序+6"], ["改革: 中常侍"]], "张燕"),
    ("黑山大殿", "Black Mountain Grand Hall", "public_order", [["土匪收入+280", "公共秩序+10"], ["改革: 州郡刺史(Provincial Inspectors)"]], "张燕"),
    # 郑姜 - 匪盗
    ("寄身地", "Bandit Hideout", "military", [["土匪收入+50", "公共秩序+2"], []], "郑姜(Zheng Jiang)"),
    ("匪窝", "Bandit Den", "military", [["土匪收入+100", "公共秩序+4"], []], "郑姜"),
    ("贼巢", "Bandit Lair", "military", [["土匪收入+150", "公共秩序+6"], []], "郑姜"),
    ("山寨", "Bandit Mountain Fort", "military", [["土匪收入+200", "公共秩序+8"], ["改革: 赋与佃器"]], "郑姜"),
    ("大寨", "Grand Bandit Fort", "military", [["土匪收入+300", "公共秩序+12"], ["改革: 地主豪族"]], "郑姜"),
    # 郑姜 - 贡堂
    ("贡庙", "Tribute Shrine", "income", [["战利品+10%", "附庸进贡+10%"], []], "郑姜"),
    ("贡堂", "Tribute Hall", "income", [["战利品+15%", "附庸进贡+15%"], []], "郑姜"),
    ("贡庭", "Tribute Court", "income", [["战利品+20%", "附庸进贡+20%"], []], "郑姜"),
    ("纷贡庭", "Grand Tribute Court", "income", [["战利品+30%", "附庸进贡+30%"], []], "郑姜"),
    ("贡殿", "Tribute Palace", "income", [["战利品+40%", "附庸进贡+40%"], []], "郑姜"),
    # 董卓 - 强征
    ("募兵所(董卓)", "Enforced Conscription Office", "military", [["新征等级+2", "公共秩序+2", "人口增长-4K", "政府建筑建造成本-10%"], []], "董卓(Dong Zhuo)"),
    ("治兵场(董卓)", "Conscript Training Field", "military", [["新征等级+2", "公共秩序+3", "派系每季部曲部署+1", "人口增长-6K", "政府建筑建造成本-10%"], []], "董卓"),
    ("讲武营(董卓)", "Conscript Training Camp", "military", [["新征等级+3", "公共秩序+4", "派系每季部曲部署+2", "重新部署费用-5%", "人口增长-8K"], []], "董卓"),
    ("强募军营", "Barracks of Conscription Enforcement", "military", [["新征等级+3", "公共秩序+6", "征募回合-1", "人口增长-12K"], ["改革: 家兵"]], "董卓"),
    ("叛乱军营", "Headquarters of Military Suppression", "military", [["新征等级+3", "公共秩序+8", "重新部署费用-8%", "人口增长-16K", "政府建筑建造成本-15%"], ["改革: 世袭部曲"]], "董卓"),
    # 特色地标
    ("孔圣城庙宇", "Grand Temple City of Confucius", "public_order", [["声望+5", "派系满意度+10", "经济建筑建造成本-10%"], []], "渤海势力(Bohai)地标，1回合/2500金"),
]
_f_tier = 0
_f_prev = None
_f_last_fac = None
_f_last_type = None
for zh, en, btype, fx_req, fac in faction_blds:
    if zh == "__CHAIN__":
        _f_tier = 0
        _f_prev = None
        continue
    fx, req = fx_req[0], fx_req[1]
    fac_key = fac.split("(")[0].strip()
    if fac_key != _f_last_fac or btype != _f_last_type:
        _f_tier = 0
        _f_prev = None
    _f_tier += 1
    _f_last_fac, _f_last_type = fac_key, btype
    bld(zh, en, btype, _f_tier, _f_prev, [], 0, 1, 0, fx, req, fac, "派系特殊建筑")
    _f_prev = zh

# ============================================================
# 32. 黄巾军 Yellow Turban buildings
# ============================================================
ytr = [
    ("黎庶营", "Refugee Shelters", "income", [["农民收入+10%", "人口增长+2K"], []]),
    ("基本劳工寓所", "Basic Labourer Accommodation", "income", [["工业收入+15%", "人口增长+6K"], []]),
    ("劳工家庭寓所", "Labourer Family Houses", "income", [["工业收入+20%", "人口增长+12K"], []]),
    ("劳工社区", "Labourer Communes", "income", [["商业收入+30%", "工业收入+25%", "人口增长+25K", "相邻-2K"], ["改革: 教化邻里(Neighbourly Tutoring)"]]),
    ("劳工区", "Labourer Housing District", "income", [["商业收入+40%", "工业收入+30%", "人口增长+50K", "相邻-4K"], ["改革: 完美建造(Perfect Construction)"]]),
        ("__CHAIN__",),
("众工坊", "Communal Workshops (YTR)", "income", [["工业收入+10%", "人口增长+4K"], []]),
    ("公共工坊", "Public Workshops (YTR)", "income", [["工业收入+15%", "人口增长+8K"], []]),
    ("匠作院", "Artisan Court (YTR)", "income", [["工业收入+20%", "商业收入+10%", "人口增长+12K"], []]),
    ("协造堂", "Cooperative Hall", "income", [["工业收入+30%", "商业收入+15%", "人口增长+20K", "解锁手工业者"], ["改革: 融协筑术(Cooperative Building)"]]),
    ("奢侈品作坊", "Luxury Workshop", "income", [["工业收入+40%", "商业收入+20%", "人口增长+30K", "解锁手工业者"], ["改革: 广智(Knowledge)"]]),
        ("__CHAIN__",),
("祥结织坊", "Auspicious Weaving Workshop", "income", [["商业收入+10%", "人口增长+4K"], []]),
    ("神符工坊", "Talisman Workshop", "income", [["商业收入+15%", "人口增长+8K"], []]),
    ("神符雕坊", "Talisman Carving Workshop", "income", [["商业收入+20%", "人口增长+12K"], []]),
    ("精琢坊", "Fine Carving Workshop", "income", [["商业收入+30%", "人口增长+20K", "解锁匠师"], ["改革: 广智"]]),
    ("宝雕堂", "Treasure Carving Hall", "income", [["商业收入+40%", "人口增长+30K", "解锁匠师"], ["改革: 融协筑术"]]),
        ("__CHAIN__",),
("流民避所", "Refugee Shelter (YTR)", "food", [["农民收入+10%", "人口增长+2K"], []]),
    ("农人寓所", "Basic Peasant Accommodations", "food", [["农民收入+15%", "人口增长+4K"], []]),
    ("农家寓所", "Peasant Family Houses", "food", [["农民收入+20%", "粮食产量+25%", "人口增长+8K"], []]),
    ("农社", "Peasant Communes", "food", [["农民收入+25%", "粮食产量+50%", "人口增长+12K", "相邻-1K"], ["改革: 教化邻里"]]),
    ("围栏农人宿区", "Walled Peasant Housing District", "food", [["农民收入+30%", "粮食产量+100%", "人口增长+25K", "相邻-2K"], ["改革: 完美建造"]]),
        ("__CHAIN__",),
("农田地", "Farm Plots", "food", [["粮食+2", "农民收入+60"], []]),
    ("公共佃农耕地", "Public Tenant Farmland", "food", [["粮食+3", "农民收入+80"], []]),
    ("公共灌溉农田", "Public Irrigated Farmland", "food", [["粮食+4", "农民收入+100"], []]),
    ("公共农庄", "Public Farming Estate", "food", [["粮食+6", "农民收入+120"], ["改革: 民利优先(People's Welfare)"]]),
    ("丰饶农庄", "Prosperous Farming Estate", "food", [["粮食+8", "农民收入+150"], ["改革: 长久筑法(Durable Construction)"]]),
        ("__CHAIN__",),
("酒舍", "Tavern", "public_order", [["公共秩序+2", "商业收入+40"], []]),
    ("酒屋", "Alehouse", "public_order", [["公共秩序+4", "商业收入+70"], []]),
    ("游艺馆", "Entertainment Hall", "public_order", [["公共秩序+6", "商业收入+100"], []]),
    ("公共酒肆", "Communal Tavern", "public_order", [["公共秩序+8", "商业收入+130"], ["改革: 教化邻里"]]),
    ("公庭场", "Communal Gathering Ground", "public_order", [["公共秩序+12", "商业收入+170"], ["改革: 完美建造"]]),
        ("__CHAIN__",),
("店家", "Shop (YTR)", "income", [["商业收入+50", "商业收入+5%"], []]),
    ("集市", "Market (YTR)", "income", [["商业收入+90", "商业收入+10%"], []]),
    ("市令署", "Market Office (YTR)", "income", [["商业收入+130", "商业收入+15%"], []]),
    ("货栈", "Merchant Warehouse (YTR)", "income", [["商业收入+170", "商业收入+20%", "解锁巨贾"], ["改革: 教化邻里"]]),
    ("会商堂", "Commercial Hall (YTR)", "income", [["商业收入+220", "商业收入+25%", "解锁巨贾"], ["改革: 完美建造"]]),
        ("__CHAIN__",),
("义兵岗", "Righteous Soldier Post", "military", [["新征部队初始等级+2"], []]),
    ("兄弟治兵场", "Brotherhood Training Field", "military", [["新征部队初始等级+2", "派系每季部曲部署+1"], []]),
    ("传武院", "Martial Arts Academy (YTR)", "military", [["新征部队初始等级+3", "派系每季部曲部署+1"], []]),
        ("__CHAIN__",),
("铁匠铺(黄巾)", "Blacksmith (YTR)", "military", [["招募费用-5%", "工业收入+5%"], []]),
    ("锻造工坊", "Forging Workshop", "military", [["招募费用-10%", "工业收入+10%"], []]),
        ("__CHAIN__",),
("太平祠坛", "Way of Peace Shrine", "public_order", [["公共秩序+2", "宗教热情-5"], []]),
    ("天道坛", "Way of Heaven Altar", "public_order", [["公共秩序+4", "宗教热情-10"], []]),
    ("天道大坛", "Grand Way of Heaven Altar", "public_order", [["公共秩序+8", "宗教热情-15"], ["改革: 融协筑术"]]),
        ("__CHAIN__",),
("同会场", "Meeting Hall (YTR)", "public_order", [["公共秩序+2", "人口增长+4K"], []]),
    ("黄巾隐所", "Yellow Turban Hideout", "public_order", [["公共秩序+4", "人口增长+8K"], []]),
    ("万民会", "Assembly of the Myriad", "public_order", [["公共秩序+6", "人口增长+12K"], []]),
    ("渠帅府", "Chieftain's Court", "public_order", [["公共秩序+8", "人口增长+20K"], ["改革: 民利优先"]]),
    ("黄巾总寨", "Yellow Turban Headquarters", "public_order", [["公共秩序+12", "人口增长+30K"], ["改革: 长久筑法"]]),
        ("__CHAIN__",),
("经卷屋", "Scripture House", "research", [["研究速率+3%", "公共秩序+1"], []]),
    ("辩学阁", "Scholarly Debate Hall", "research", [["研究速率+6%", "公共秩序+2"], []]),
    ("集学屋", "Learning House", "research", [["研究速率+9%", "公共秩序+3"], []]),
    ("学文库", "Library (YTR)", "research", [["研究速率+12%", "公共秩序+4"], ["改革: 广智"]]),
    ("启明之堂", "Hall of Enlightenment", "research", [["研究速率+15%", "公共秩序+5"], ["改革: 融协筑术"]]),
    # 何仪 - 医士
        ("__CHAIN__",),
("乡村医士寓所", "Rural Physician's Residence", "public_order", [["派系人物生命值+5%", "公共秩序+2"], []], "何仪(He Yi)"),
    ("针灸师寓所", "Acupuncturist's Residence", "public_order", [["派系人物生命值+10%", "公共秩序+4"], []], "何仪"),
    ("药坊", "Pharmacy", "public_order", [["派系人物生命值+15%", "公共秩序+6"], []], "何仪"),
    ("药师房", "Apothecary's Studio", "public_order", [["派系人物生命值+20%", "公共秩序+8"], ["改革: 教化邻里"]], "何仪"),
    ("天悯阁", "Hall of Heavenly Mercy", "public_order", [["派系人物生命值+30%", "公共秩序+12"], ["改革: 完美建筑"]], "何仪"),
    # 龚都 - 游击
        ("__CHAIN__",),
("收集点", "Collection Point", "military", [["伏击成功率+5%", "军事补给+5"], []], "龚都(Gong Du)"),
    ("藏武库", "Hidden Armoury", "military", [["伏击成功率+10%", "军事补给+10"], []], "龚都"),
    ("暗营", "Hidden Camp", "military", [["伏击成功率+15%", "军事补给+15"], []], "龚都"),
    ("营垒", "Hidden Fort", "military", [["伏击成功率+20%", "军事补给+20"], ["改革: 民利优先"]], "龚都"),
    ("暗堡", "Hidden Bastion", "military", [["伏击成功率+30%", "军事补给+30"], ["改革: 长久筑法"]], "龚都"),
    # 黄邵 - 园林
        ("__CHAIN__",),
("静园", "Tranquil Garden", "public_order", [["公共秩序+2", "人物经验+2%(派系)"], []], "黄邵(Huang Shao)"),
    ("冥思园", "Meditation Garden", "public_order", [["公共秩序+4", "人物经验+4%(派系)"], []], "黄邵"),
    ("水景园", "Water Garden", "public_order", [["公共秩序+6", "人物经验+6%(派系)"], []], "黄邵"),
    ("迷苑", "Maze Garden", "public_order", [["公共秩序+8", "人物经验+8%(派系)"], ["改革: 广智"]], "黄邵"),
    ("天宇苑", "Heavenly Garden", "public_order", [["公共秩序+12", "人物经验+10%(派系)"], ["改革: 融协筑术"]], "黄邵"),
]
chain_keys = []
_ytr_tier = 0
_ytr_prev = None
_ytr_last_fac = None
_ytr_last_type = None
for item in ytr:
    if item[0] == "__CHAIN__":
        _ytr_tier = 0
        _ytr_prev = None
        continue
    zh, en, btype, fx_req = item[:4]
    fx, req = fx_req[0], fx_req[1]
    fac = item[4] if len(item) > 4 else "黄巾军(Yellow Turbans)"
    fac_key = fac.split("(")[0].strip()
    if fac_key != _ytr_last_fac or btype != _ytr_last_type:
        _ytr_tier = 0
        _ytr_prev = None
    _ytr_tier += 1
    _ytr_last_fac, _ytr_last_type = fac_key, btype
    bld(zh, en, btype, _ytr_tier, _ytr_prev, [], 0, 1, 0, fx, req, fac, "黄巾军特殊建筑序列")
    _ytr_prev = zh

# ============================================================
# 33. 盗匪营地建筑 Bandit Camp (补丁1.5)
# ============================================================
bandit = [
    ("集结地", "Mustering Grounds", "military", ["重新部署费用-5%(派系)", "补给+10%(本地)", "相邻敌军公共秩序-3"], [], "盗匪派系(Bandits)"),
    ("预备营", "Preparatory Camp", "research", ["研究速率+5%(派系)", "间谍掩护+1(派系)"], [], "盗匪派系"),
    ("粮帐", "Food Tents", "food", ["人口增长+4K", "公共秩序+2", "战利品+5%"], [], "盗匪派系"),
    ("黑市", "Black Market", "income", ["土匪收入+100(本地)"], [], "盗匪派系"),
    ("山越营地", "Shanyue Camp", "food", ["粮食产量+10%", "山越部族科技研究+5%", "额外征募山越士兵"], [], "严白虎(Yan Baihu)专属"),
]
for zh, en, btype, fx, req, fac in bandit:
    bld(zh, en, btype, 1, None, [], 500, 1, 0, fx, req, fac, "盗匪营地建筑(1.5.0补丁，小城额外栏位)")

# ============================================================
# 34. 南蛮 Nanman (Furious Wild DLC)
# ============================================================
nanman = [
    ("祭祀之地", "Sites of Worship", "public_order", ["声望+5", "人口增长+10K", "公共秩序+4", "本地腐败-5%"], [], "南蛮(Nanman)"),
    ("手工艺行会", "Artisanal Guilds", "income", ["全部收入+10%", "建造成本-5%", "相邻郡国腐败-5%"], [], "南蛮"),
    ("欢庆之所", "Places of Festivity", "income", ["人口增长+10K", "人物经验+5%(派系)", "公共秩序+4", "商业收入+10%"], [], "南蛮"),
    ("南蛮军武设施", "Nanman Military Infrastructure", "military", ["军事补给+10(相邻)", "工业收入+10%", "粮食储备+20", "额外大象/猛虎掷石兵征募"], [], "南蛮"),
]
for zh, en, btype, fx, req, fac in nanman:
    bld(zh, en, btype, 1, None, [], 0, 1, 0, fx, req, fac, "南蛮(DLC荒芜之地/Furious Wild)通用独特链")

# ============================================================
# 35. 战锤 Total War: Warhammer 参考建筑 (附赠)
# ============================================================
wh = [
    ("混沌要塞(1级)", "Chaos Keep", "government", ["人口盈余+1", "建造栏位+1", "提供驻军"], ["黑暗要塞城镇"], "混沌勇士(WoC)"),
    ("混沌堡垒(2级)", "Chaos Fort", "government", ["人口盈余+1", "建造栏位+2", "收入+400", "提供驻军"], [], "混沌勇士"),
    ("黑暗棱堡(3级)", "Dark Redoubt", "government", ["人口盈余+2", "建造栏位+3", "收入+500", "提供驻军"], [], "混沌勇士"),
    ("黑暗要塞(4级)", "Dark Fortress", "government", ["人口盈余+4", "建造栏位+5", "收入+800", "防御补给+1500", "增长+90", "腐败+2", "城墙", "提供驻军"], [], "混沌勇士"),
    ("至高黑暗要塞(5级)", "Exalted Dark Fortress", "government", ["人口盈余+5", "建造栏位+6", "收入+1200", "防御补给+2000", "增长+120", "腐败+2", "城墙", "提供驻军"], [], "混沌勇士"),
    ("劳工征募局", "Labour Conscription Bureau", "income", ["增长+10", "建造成本-4%(本地省)", "阳谐和+1", "无法建造茶馆"], ["阴阳建筑互斥"], "震旦(Grand Cathay)"),
    ("茶馆(震旦)", "Tea Parlour (Cathay)", "income", ["增长+10", "所有建筑收入+2%(本地省)", "阴谐和+1", "无法建造劳工征募局"], ["阴阳建筑互斥"], "震旦"),
    ("炖菜厨房", "Stew Kitch'n", "food", ["收入+50", "防御补给+1000", "增长+15", "腐败-1", "建造栏位+1", "城墙", "提供驻军"], [], "食人魔王国(Ogre Kingdoms)"),
    ("恐虐炽炉", "Khornate Calefactor", "military", ["收入+40", "解锁招募"], [], "恐虐(Khorne)"),
    ("屠戮领域", "Domain of Slaughter", "military", ["收入+80", "解锁招募"], [], "恐虐"),
    ("巨墙门楼", "Bastion Gatehouse", "military", ["收入+100", "防御补给+1000", "增长+20", "围城损耗-30%", "腐败-2", "城墙", "提供驻军", "可突围出击", "发现混沌邪教+25"], ["仅巨墙(The Great Bastion)"], "震旦"),
]
for zh, en, btype, fx, req, fac in wh:
    bld(zh, en, btype, 1, None, [], 0, 1, 0, fx, req, fac, "参考: 全面战争: 战锤3建筑数据(附赠)")

# ============================================================
# Write JSON
# ============================================================
data = {
    "game": "全面战争",
    "game_en": "Total War",
    "subtitle": "Three Kingdoms / 三国 (附: 战锤 Warhammer 参考)",
    "category": "buildings",
    "source_notes": "数据来源: 3DM攻略站全建筑图鉴(60页)、Total War Fandom Wiki、TWC Wiki(TWCenter)、honga.net Royal Military Academy数据库、SteamXO/电玩狂人/9game攻略、Prima Games DLC指南、NoobFeed。部分数值(尤其建造成本/时间)因来源不同存在差异,已标注最常引用数值。",
    "buildings": B,
}
with open(r"D:\pyFramework\web-search\全面战争\buildings.json", "w", encoding="utf-8") as f:
    json.dump(data, f, ensure_ascii=False, indent=2)
print("total buildings:", len(B))
