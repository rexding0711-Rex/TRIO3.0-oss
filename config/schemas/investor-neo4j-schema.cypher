// ============================================================
// TRIO-Investor Neo4j Schema v1.0
// 用途：一级市场投资人项目图谱
// 执行方式：cypher-shell -f investor-schema.cypher
// 或在 Neo4j Browser 中逐段执行
// ============================================================

// ═══ 约束与索引 ═══

// 公司节点——唯一标识为公司全名
CREATE CONSTRAINT company_name IF NOT EXISTS
FOR (c:Company) REQUIRE c.name IS UNIQUE;

// 创始人节点——同名+同教育背景视为同一人
CREATE CONSTRAINT founder_identity IF NOT EXISTS
FOR (f:Founder) REQUIRE (f.name, f.education) IS NODE KEY;

// 基金节点
CREATE CONSTRAINT fund_name IF NOT EXISTS
FOR (f:Fund) REQUIRE f.name IS UNIQUE;

// LP 节点
CREATE CONSTRAINT lp_name IF NOT EXISTS
FOR (lp:LP) REQUIRE lp.name IS UNIQUE;

// 赛道节点
CREATE CONSTRAINT sector_name IF NOT EXISTS
FOR (s:Sector) REQUIRE s.name IS UNIQUE;

// 交易记录——同一公司同一轮次唯一
CREATE CONSTRAINT deal_unique IF NOT EXISTS
FOR (d:Deal) REQUIRE (d.company_name, d.round) IS NODE KEY;

// 决策记录
CREATE CONSTRAINT decision_unique IF NOT EXISTS
FOR (d:Decision) REQUIRE (d.project, d.date) IS NODE KEY;

// ═══ 节点标签体系 ═══

// Company — 被投/待投公司
// 属性：name, stage(seed/A/B/C/pre-IPO), sector, founded_year,
//        headquarters, valuation, revenue, growth_rate, gross_margin,
//        employee_count, business_model, description, source_url, status

// Founder — 创始人/核心团队
// 属性：name, education, previous_company, role, linkedin_url,
//        strengths, risks, contact_status, notes

// Fund — 投资机构
// 属性：name, type(VC/PE/CVC/天使/FOF), aum, founded_year,
//        stage_focus, sector_focus, headquarters, lp_base

// LP — 有限合伙人
// 属性：name, type(母基金/家族办公室/高净值/养老金/险资/上市公司),
//        headquarters, commitment_amount, relationship_status

// Deal — 交易记录
// 属性：company_name, round, amount, valuation, date, status(pipeline/ts/closed/pass),
//        lead_investor, co_investors, terms_summary, source

// Sector — 赛道分类
// 属性：name, parent_sector, description, heat_score(1-10),
//        total_market_size, growth_rate, active_funds_count

// Decision — 决策记录
// 属性：project, date, decision_type(初筛/TS/投委会/退出), verdict(投/不投/跟进入),
//        confidence(1-5), thesis, concerns, outcome(如已退出), lessons

// Exit — 退出记录
// 属性：date, type(IPO/并购/老股转让/清算), amount, moic, irr,
//        holding_period_months, notes

// Thesis — 投资主题
// 属性：name, description, start_date, end_date, status(active/closed),
//        target_return, sector_focus, stage_focus

// ═══ 关系类型 ═══

// 公司之间
// (:Company)-[:COMPETES_WITH {intensity: 'direct'|'indirect'}]->(:Company)
// (:Company)-[:SUPPLIER_TO {product: '...'}]->(:Company)
// (:Company)-[:CUSTOMER_OF {product: '...'}]->(:Company)
// (:Company)-[:PARTNER_WITH {scope: '...'}]->(:Company)
// (:Company)-[:ACQUIRED_BY {date: '...'}]->(:Company)

// 人与公司
// (:Founder)-[:FOUNDED {date: '...', role: 'CEO'|'CTO'|...}]->(:Company)
// (:Founder)-[:WORKED_AT {period: '...', role: '...'}]->(:Company)
// (:Founder)-[:ADVISOR_TO]->(:Company)
// (:Founder)-[:LEFT {date: '...', reason: '...'}]->(:Company)

// 投资关系
// (:Fund)-[:INVESTED_IN {round: '...', date: '...', amount: '...'}]->(:Company)
// (:Fund)-[:LEAD_IN {round: '...', date: '...'}]->(:Company)
// (:Deal)-[:INVESTMENT_IN]->(:Company)
// (:Deal)-[:LED_BY]->(:Fund)

// 赛道归属
// (:Company)-[:IN_SECTOR]->(:Sector)
// (:Fund)-[:FOCUSES_ON {weight: 1-10}]->(:Sector)

// LP 关系
// (:LP)-[:COMMITTED_TO {amount: '...', date: '...', fund_vintage: '...'}]->(:Fund)

// ═══ 常用查询模板 ═══

// 1. 查看完整管线
// MATCH (d:Deal)-[:INVESTMENT_IN]->(c:Company)
// OPTIONAL MATCH (c)-[:IN_SECTOR]->(s:Sector)
// RETURN d.status, c.name, c.stage, s.name, d.amount, d.date
// ORDER BY d.date DESC

// 2. 按赛道统计
// MATCH (c:Company)-[:IN_SECTOR]->(s:Sector)
// RETURN s.name, count(c) as companies, avg(c.revenue) as avg_revenue
// ORDER BY companies DESC

// 3. 找相似项目（同赛道+同阶段）
// MATCH (c:Company {name: $name})-[:IN_SECTOR]->(s:Sector)
// MATCH (other:Company)-[:IN_SECTOR]->(s)
// WHERE other.name <> c.name AND other.stage = c.stage
// RETURN other.name, other.valuation, other.revenue

// 4. 创始人网络
// MATCH (f:Founder)-[:FOUNDED]->(c:Company)
// OPTIONAL MATCH (f)-[:WORKED_AT]->(prev:Company)
// OPTIONAL MATCH (f2:Founder)-[:FOUNDED]->(c)
// RETURN f.name, c.name, collect(prev.name) as previous_companies

// 5. 竞争格局
// MATCH (c:Company {name: $name})-[:COMPETES_WITH]->(competitor:Company)
// OPTIONAL MATCH (competitor)<-[:INVESTED_IN]-(fund:Fund)
// RETURN competitor.name, competitor.stage, competitor.valuation,
//        collect(fund.name) as investors

// 6. 退出复盘（按赛道）
// MATCH (e:Exit)-[:EXIT_OF]->(c:Company)-[:IN_SECTOR]->(s:Sector)
// RETURN s.name, count(e) as exits,
//        avg(e.moic) as avg_moic, avg(e.irr) as avg_irr,
//        avg(e.holding_period_months) as avg_hold_months
// ORDER BY avg_moic DESC

// 7. 决策质量追踪
// MATCH (d:Decision)
// WHERE d.outcome IS NOT NULL
// RETURN d.decision_type, d.verdict,
//        count(d) as count,
//        avg(CASE WHEN d.verdict = '投' AND d.outcome > 1 THEN 1 ELSE 0 END) as win_rate
// ORDER BY d.decision_type
