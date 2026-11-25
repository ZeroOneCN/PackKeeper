'use strict';

/** IndexedDB 数据库名。 */
const DB_NAME = 'packkeeper-report';
/** 对象仓库名。 */
const STORE_NAME = 'datasets';
/** 固定主键：只保留最近一次导入。 */
const DATASET_KEY = 'latest';

/** 包裹状态中文名。 */
const PARCEL_STATUS = {
  pending: '待认领',
  assigned: '已分配',
  inbound: '已入库',
  outbound: '已转寄',
  done: '已完成',
  exception: '异常件',
};
/** 包裹来源中文名。 */
const PARCEL_SOURCE = { scan: '扫码', ocr: '面单', manual: '手动' };
/** 订单状态中文名。 */
const ORDER_STATUS = { created: '已建单' };
/** 履约路径中文名。 */
const ORDER_ROUTE = { warehouse: '仓库', direct: '直送' };
/** 审计动作中文名。 */
const AUDIT_ACTION = {
  'platform.create': '新增平台',
  'platform.update': '修改平台',
  'platform.delete': '删除平台',
  'account.create': '新增账号',
  'account.update': '修改账号',
  'account.delete': '删除账号',
  'parcel.create': '包裹入库',
  'parcel.delete': '删除包裹',
  'parcel.assigned_by_order': '订单自动关联包裹',
  'order.create': '新增订单',
  'order.tracking': '补录物流单号',
  'product.create': '新增商品',
  'product.update': '修改商品',
  'product.delete': '删除商品',
  'shipment.create': '新建转寄批次',
  'shipment.update': '修改转寄批次',
  'shipment.delete': '删除转寄批次',
};

/** 管理后台页签。 */
const TABS = [
  'overview',
  'orders',
  'parcels',
  'shipments',
  'accounts',
  'platforms',
  'products',
  'audit',
];

/** 页面状态。 */
const state = { dataset: null, range: 'all', tab: 'overview' };

/** 各数据页签最近一次渲染的行，用于导出与当前筛选保持一致。 */
const lastRows = {};

/** 快捷获取元素。 */
const $ = (id) => document.getElementById(id);

/**
 * 转义 HTML 特殊字符，避免导入内容破坏表格结构。
 * @param {*} value 原始值
 * @returns {string} 可安全插入 innerHTML 的文本
 */
function esc(value) {
  return String(value == null ? '' : value)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

/**
 * 金额格式化：¥ 千分位 + 两位小数。
 * @param {number} value 金额
 * @returns {string} 格式化文本
 */
function money(value) {
  const n = Number(value) || 0;
  return '¥' + n.toLocaleString('zh-CN', {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  });
}

/**
 * 数量格式化：千分位整数。
 * @param {number} value 数量
 * @returns {string} 格式化文本
 */
function count(value) {
  return (Number(value) || 0).toLocaleString('zh-CN');
}

/**
 * 时间戳格式化。
 * @param {number|null} ms 毫秒时间戳
 * @param {boolean} withTime 是否包含时分
 * @returns {string} 本地时间文本
 */
function fmtDate(ms, withTime = true) {
  if (!ms) return '—';
  const d = new Date(Number(ms));
  if (Number.isNaN(d.getTime())) return '—';
  const pad = (n) => String(n).padStart(2, '0');
  const date = `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
  return withTime ? `${date} ${pad(d.getHours())}:${pad(d.getMinutes())}` : date;
}

/** 生成文件名用的时间戳。 */
function stamp() {
  const d = new Date();
  const pad = (n) => String(n).padStart(2, '0');
  return `${d.getFullYear()}${pad(d.getMonth() + 1)}${pad(d.getDate())}-${pad(d.getHours())}${pad(d.getMinutes())}`;
}

/** 提示浮层。 */
let toastTimer = null;
/**
 * 显示底部提示。
 * @param {string} message 提示文案
 */
function toast(message) {
  const node = $('toast');
  node.textContent = message;
  node.hidden = false;
  requestAnimationFrame(() => node.classList.add('show'));
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => {
    node.classList.remove('show');
    setTimeout(() => {
      node.hidden = true;
    }, 220);
  }, 2200);
}

/** 打开 IndexedDB。 */
function openDb() {
  return new Promise((resolve, reject) => {
    const request = indexedDB.open(DB_NAME, 1);
    request.onupgradeneeded = () => {
      const db = request.result;
      if (!db.objectStoreNames.contains(STORE_NAME)) {
        db.createObjectStore(STORE_NAME);
      }
    };
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(request.error);
  });
}

/**
 * 读取已保存的数据集。
 * @returns {Promise<object|null>} 数据集或 null
 */
async function loadDataset() {
  const db = await openDb();
  return new Promise((resolve, reject) => {
    const tx = db.transaction(STORE_NAME, 'readonly');
    const request = tx.objectStore(STORE_NAME).get(DATASET_KEY);
    request.onsuccess = () => resolve(request.result || null);
    request.onerror = () => reject(request.error);
  });
}

/**
 * 保存数据集（覆盖上一次）。
 * @param {object} dataset 数据集
 * @returns {Promise<void>}
 */
async function saveDataset(dataset) {
  const db = await openDb();
  return new Promise((resolve, reject) => {
    const tx = db.transaction(STORE_NAME, 'readwrite');
    tx.objectStore(STORE_NAME).put(dataset, DATASET_KEY);
    tx.oncomplete = () => resolve();
    tx.onerror = () => reject(tx.error);
  });
}

/**
 * 清空已保存的数据集。
 * @returns {Promise<void>}
 */
async function clearDataset() {
  const db = await openDb();
  return new Promise((resolve, reject) => {
    const tx = db.transaction(STORE_NAME, 'readwrite');
    tx.objectStore(STORE_NAME).delete(DATASET_KEY);
    tx.oncomplete = () => resolve();
    tx.onerror = () => reject(tx.error);
  });
}

/**
 * 读取备份 JSON 中的业务表，缺失字段按空数组处理。
 * @returns {{platforms:Array,accounts:Array,products:Array,parcels:Array,orders:Array,
 *   shipments:Array,scan_events:Array,audit_logs:Array}} 业务表集合
 */
function tables() {
  const data = state.dataset && state.dataset.payload && state.dataset.payload.data
    ? state.dataset.payload.data
    : {};
  const pick = (key) => (Array.isArray(data[key]) ? data[key] : []);
  return {
    platforms: pick('platforms'),
    accounts: pick('accounts'),
    products: pick('products'),
    parcels: pick('parcels'),
    orders: pick('orders'),
    shipments: pick('shipments'),
    scan_events: pick('scan_events'),
    audit_logs: pick('audit_logs'),
  };
}

/**
 * 计算当前统计区间的起始时间。
 * @param {string} range all | month | quarter | year
 * @returns {number|null} 起始毫秒时间戳，all 返回 null
 */
function rangeStart(range) {
  const now = new Date();
  if (range === 'month') return new Date(now.getFullYear(), now.getMonth(), 1).getTime();
  if (range === 'quarter') return new Date(now.getFullYear(), now.getMonth() - 2, 1).getTime();
  if (range === 'year') return new Date(now.getFullYear(), 0, 1).getTime();
  return null;
}

/** 区间中文名。 */
const RANGE_LABEL = { all: '全部数据', month: '本月', quarter: '近 3 个月', year: '本年' };

/**
 * 汇总订单经营数据。
 * @param {Array} orders 订单表
 * @returns {{orderCount:number,sales:number,cost:number,profit:number}} 汇总结果
 */
function sumOrders(orders) {
  let sales = 0;
  let cost = 0;
  for (const order of orders) {
    sales += Number(order.amount) || 0;
    cost += Number(order.cost) || 0;
  }
  return { orderCount: orders.length, sales, cost, profit: sales - cost };
}

/**
 * 汇总转寄批次的快递费。
 * @param {Array} shipments 转寄批次表
 * @returns {{shipmentCount:number,fee:number}} 批次数量与快递费合计
 */
function sumShipments(shipments) {
  let fee = 0;
  for (const shipment of shipments) {
    fee += Number(shipment.fee) || 0;
  }
  return { shipmentCount: shipments.length, fee };
}

/**
 * 统计每个转寄批次关联的包裹数量。
 * @param {Array} parcels 包裹表
 * @returns {Map<string,number>} 批次 id → 包裹数
 */
function parcelCountByShipment(parcels) {
  const map = new Map();
  for (const parcel of parcels) {
    if (!parcel.shipment_id) continue;
    map.set(parcel.shipment_id, (map.get(parcel.shipment_id) || 0) + 1);
  }
  return map;
}

/**
 * 按分区键归集订单金额。
 * @param {Array} orders 订单表
 * @param {Function} keyFn 分区函数
 * @returns {Map<string,{orderCount:number,sales:number,cost:number,profit:number}>}
 */
function groupOrders(orders, keyFn) {
  const map = new Map();
  for (const order of orders) {
    const key = keyFn(order);
    if (!map.has(key)) {
      map.set(key, { orderCount: 0, sales: 0, cost: 0, profit: 0 });
    }
    const bucket = map.get(key);
    const amount = Number(order.amount) || 0;
    const cost = Number(order.cost) || 0;
    bucket.orderCount += 1;
    bucket.sales += amount;
    bucket.cost += cost;
    bucket.profit += amount - cost;
  }
  return map;
}

/**
 * 生成表格 HTML。
 *
 * 单元格支持字符串、数字，或 `{html, text}` 对象：html 用于页面展示，
 * text 用于导出 CSV，避免金额等展示文本混入原始数据。
 *
 * @param {string[]} headers 表头
 * @param {Array<Array<*>>} rows 行数据
 * @param {number[]} numericCols 需要右对齐的列下标
 * @returns {string} 表格 HTML
 */
function tableHtml(headers, rows, numericCols = []) {
  const head = headers
    .map((h, i) => `<th class="${numericCols.includes(i) ? 'num' : ''}">${esc(h)}</th>`)
    .join('');
  const body = rows
    .map(
      (row) =>
        '<tr>' +
        row
          .map((cell, i) => {
            const cls = numericCols.includes(i) ? 'num' : '';
            const isObj = cell && typeof cell === 'object';
            const value = isObj ? cell.html : esc(cell);
            return `<td class="${cls}">${value}</td>`;
          })
          .join('') +
        '</tr>',
    )
    .join('');
  return `<table><thead><tr>${head}</tr></thead><tbody>${body}</tbody></table>`;
}

/** 构建账号、平台、商品索引。 */
function buildIndexes(t) {
  return {
    platformById: new Map(t.platforms.map((p) => [p.id, p])),
    accountById: new Map(t.accounts.map((a) => [a.id, a])),
    productById: new Map(t.products.map((p) => [p.id, p])),
  };
}

/**
 * 取账号所属平台。
 * @param {object} idx 索引
 * @param {object|null} account 账号
 * @returns {object|null} 平台
 */
function platformOfAccount(idx, account) {
  return account ? idx.platformById.get(account.platform_id) || null : null;
}

/**
 * 取订单所属平台。
 * @param {object} idx 索引
 * @param {object} order 订单
 * @returns {object|null} 平台
 */
function platformOfOrder(idx, order) {
  return platformOfAccount(idx, idx.accountById.get(order.account_id));
}

/**
 * 按关键词过滤列表。
 * @param {Array} list 数据列表
 * @param {string} keyword 关键词
 * @param {Function} fieldsFn 取可搜索文本的函数
 * @returns {Array} 过滤结果
 */
function searchList(list, keyword, fieldsFn) {
  const q = (keyword || '').trim().toLowerCase();
  if (!q) return list;
  return list.filter((item) => fieldsFn(item).join(' ').toLowerCase().includes(q));
}

/** 渲染数据概要。 */
function renderMeta(t) {
  const payload = state.dataset.payload;
  const parts = [
    `<span>数据文件：<strong>${esc(state.dataset.fileName)}</strong></span>`,
    `<span>导入时间：<strong>${esc(fmtDate(state.dataset.importedAt))}</strong></span>`,
    `<span>备份时间：<strong>${esc(fmtDate(payload.exported_at))}</strong></span>`,
    `<span>平台 ${t.platforms.length} · 账号 ${t.accounts.length} · 商品 ${t.products.length} · 订单 ${t.orders.length} · 包裹 ${t.parcels.length} · 转寄 ${t.shipments.length}</span>`,
  ];
  $('meta').innerHTML = parts.join('');
}

/**
 * 渲染 KPI 指标卡。
 * @param {object} t 业务表
 * @param {Array} orders 区间内订单
 * @param {Array} shipments 区间内转寄批次
 */
function renderKpis(t, orders, shipments) {
  const sum = sumOrders(orders);
  const ship = sumShipments(shipments);
  const pendingParcels = t.parcels.filter((p) => p.status === 'pending').length;
  const pendingOrders = t.orders.filter((o) => !o.tracking_no).length;
  const avg = sum.orderCount > 0 ? sum.sales / sum.orderCount : 0;
  const netProfit = sum.sales - sum.cost - ship.fee;
  const margin = sum.sales > 0 ? (netProfit / sum.sales) * 100 : 0;

  const cards = [
    { label: '订单数', value: count(sum.orderCount), sub: '笔' },
    { label: '销售额', value: money(sum.sales), sub: RANGE_LABEL[state.range] },
    { label: '成本', value: money(sum.cost), sub: '已录成本的订单' },
    {
      label: '快递费',
      value: money(ship.fee),
      sub: `${ship.shipmentCount} 个转寄批次`,
      tone: ship.fee > 0 ? 'warn' : '',
    },
    {
      label: '净利润',
      value: money(netProfit),
      sub: sum.sales > 0 ? `利润率 ${margin.toFixed(1)}%` : '销售额 − 成本 − 快递费',
      tone: netProfit >= 0 ? 'green' : 'red',
    },
    { label: '客单价', value: money(avg), sub: '销售额 ÷ 订单数' },
    { label: '包裹总数', value: count(t.parcels.length), sub: `待认领 ${pendingParcels} 件` },
    {
      label: '待补单号',
      value: count(pendingOrders),
      sub: '下单未回填物流单号',
      tone: pendingOrders > 0 ? 'warn' : '',
    },
    { label: '账号 / 平台', value: `${t.accounts.length} / ${t.platforms.length}`, sub: '已建档' },
  ];

  $('kpis').innerHTML = cards
    .map(
      (c) => `
      <div class="kpi">
        <div class="label">${c.label}</div>
        <div class="value ${c.tone || ''}">${esc(c.value)}</div>
        <div class="sub">${esc(c.sub)}</div>
      </div>`,
    )
    .join('');
}

/** 渲染平台与账号表现表。 */
function renderBreakdowns(t, orders) {
  const idx = buildIndexes(t);
  const platformOf = (order) => {
    const platform = platformOfOrder(idx, order);
    return platform ? platform.name : '未关联账号';
  };
  const accountOf = (order) => {
    const account = idx.accountById.get(order.account_id);
    return account ? account.alias : '未关联账号';
  };

  const platformRows = [...groupOrders(orders, platformOf).entries()]
    .sort((a, b) => b[1].sales - a[1].sales)
    .map(([name, s]) => [
      name,
      s.orderCount,
      { html: `<span class="money">${money(s.sales)}</span>` },
      money(s.cost),
      { html: `<span style="color:#02743b;font-weight:600">${money(s.profit)}</span>` },
    ]);
  $('platform-table').innerHTML = platformRows.length
    ? tableHtml(['平台', '订单数', '销售额', '成本', '毛利'], platformRows, [1, 2, 3, 4])
    : '<div class="empty-inline">当前区间暂无订单</div>';

  const accountRows = [...groupOrders(orders, accountOf).entries()]
    .sort((a, b) => b[1].sales - a[1].sales)
    .map(([name, s]) => [
      name,
      s.orderCount,
      s.sales > 0 ? money(s.sales) : '—',
      s.cost > 0 ? money(s.cost) : '—',
      { html: `<span style="color:#02743b;font-weight:600">${money(s.profit)}</span>` },
    ]);
  $('account-table').innerHTML = accountRows.length
    ? tableHtml(['账号', '订单数', '销售额', '成本', '毛利'], accountRows, [1, 2, 3, 4])
    : '<div class="empty-inline">当前区间暂无订单</div>';
}

/** 渲染近 12 个月销售趋势。 */
function renderTrend(t) {
  const now = new Date();
  const windowStart = new Date(now.getFullYear(), now.getMonth() - 11, 1).getTime();
  let latest = 0;
  for (const order of t.orders) {
    latest = Math.max(latest, Number(order.ordered_at) || 0);
  }
  const hasRecent = t.orders.some((order) => (Number(order.ordered_at) || 0) >= windowStart);
  // 若订单都早于近 12 个月，则以最近一笔订单所在月为终点，避免整张图空白。
  const anchor = hasRecent || latest === 0 ? now : new Date(latest);
  const months = [];
  for (let i = 11; i >= 0; i -= 1) {
    const d = new Date(anchor.getFullYear(), anchor.getMonth() - i, 1);
    months.push({
      key: `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}`,
      label: `${d.getMonth() + 1}月`,
      current: i === 0,
    });
  }
  const buckets = new Map(months.map((m) => [m.key, { sales: 0, orderCount: 0 }]));
  for (const order of t.orders) {
    const ms = Number(order.ordered_at) || 0;
    if (!ms) continue;
    const d = new Date(ms);
    const key = `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}`;
    const bucket = buckets.get(key);
    if (!bucket) continue;
    bucket.sales += Number(order.amount) || 0;
    bucket.orderCount += 1;
  }
  const max = Math.max(...months.map((m) => buckets.get(m.key).sales), 1);
  $('trend').innerHTML = months
    .map((m) => {
      const bucket = buckets.get(m.key);
      const height = Math.max((bucket.sales / max) * 100, bucket.sales > 0 ? 4 : 1.5);
      return `
        <div class="bar" title="${m.key}：销售额 ${money(bucket.sales)}，订单 ${bucket.orderCount} 笔">
          <span class="bar-amount">${bucket.sales > 0 ? money(bucket.sales) : ''}</span>
          <div class="bar-track">
            <div class="bar-fill ${bucket.sales > 0 ? '' : 'empty'}" style="height:${height}%"></div>
          </div>
          <span class="bar-label ${m.current ? 'current' : ''}">${m.label}</span>
        </div>`;
    })
    .join('');
}

/**
 * 渲染横向条形统计列表。
 * @param {string} containerId 容器 id
 * @param {Array<{name:string,value:number}>} rows 数据行
 */
function renderStatList(containerId, rows) {
  const max = Math.max(...rows.map((r) => r.value), 1);
  const html = rows.length
    ? rows
        .map(
          (r) => `
        <div class="stat-row">
          <span class="name" title="${esc(r.name)}">${esc(r.name)}</span>
          <div class="track"><div class="fill" style="width:${Math.max((r.value / max) * 100, 2)}%"></div></div>
          <span class="count">${count(r.value)}</span>
        </div>`,
        )
        .join('')
    : '<div class="empty-inline">暂无数据</div>';
  $(containerId).innerHTML = html;
}

/** 渲染包裹状态与快递分布。 */
function renderParcels(t) {
  const statusRows = Object.entries(PARCEL_STATUS).map(([key, label]) => ({
    name: label,
    value: t.parcels.filter((p) => (p.status || 'pending') === key).length,
  }));
  const statusTotal = statusRows.reduce((sum, r) => sum + r.value, 0);
  if (statusTotal === 0) {
    renderStatList('parcel-status', []);
  } else {
    renderStatList('parcel-status', statusRows.filter((r) => r.value > 0));
  }

  const carrierMap = new Map();
  for (const parcel of t.parcels) {
    const carrier = parcel.carrier || '未知快递';
    carrierMap.set(carrier, (carrierMap.get(carrier) || 0) + 1);
  }
  const carrierRows = [...carrierMap.entries()]
    .sort((a, b) => b[1] - a[1])
    .slice(0, 8)
    .map(([name, value]) => ({ name, value }));
  renderStatList('carrier', carrierRows);
}

/** 渲染待补物流单号列表。 */
function renderPending(t) {
  const idx = buildIndexes(t);
  const pending = t.orders
    .filter((o) => !o.tracking_no)
    .sort((a, b) => (Number(b.ordered_at) || 0) - (Number(a.ordered_at) || 0));
  if (pending.length === 0) {
    $('pending-orders').innerHTML = '<div class="empty-inline">全部订单都已回填物流单号</div>';
    return;
  }
  const rows = pending.slice(0, 30).map((order) => {
    const account = idx.accountById.get(order.account_id);
    const platform = platformOfAccount(idx, account);
    return [
      order.title || '未命名订单',
      account ? `${platform ? platform.name + ' · ' : ''}${account.alias}` : '未关联账号',
      order.amount != null ? money(order.amount) : '—',
      fmtDate(order.ordered_at),
    ];
  });
  const table = tableHtml(['订单', '账号', '金额', '下单时间'], rows, [2]);
  const more =
    pending.length > 30
      ? `<div class="empty-inline">仅显示最近 30 笔，共 ${pending.length} 笔待补单号</div>`
      : '';
  $('pending-orders').innerHTML = table + more;
}

/** 渲染概览页。 */
function renderOverview() {
  const t = tables();
  const start = rangeStart(state.range);
  const orders = start == null
    ? t.orders
    : t.orders.filter((o) => (Number(o.ordered_at) || 0) >= start);
  const shipments = start == null
    ? t.shipments
    : t.shipments.filter((s) => (Number(s.shipped_at) || 0) >= start);

  $('range-hint').textContent =
    `${RANGE_LABEL[state.range]} · ${orders.length} 笔订单 · ${shipments.length} 个转寄批次`;
  renderKpis(t, orders, shipments);
  renderBreakdowns(t, orders);
  renderTrend(t);
  renderParcels(t);
  renderPending(t);
}

/**
 * 渲染订单页签。
 * @param {object} t 业务表
 * @returns {Array} 当前筛选后的订单明细
 */
function renderOrdersTab(t) {
  const idx = buildIndexes(t);
  const platformId = $('orders-platform').value;
  const filtered = searchList(t.orders, $('orders-search').value, (order) => {
    const account = idx.accountById.get(order.account_id);
    return [
      order.title,
      order.tracking_no,
      order.platform_order_no,
      order.address_text,
      account ? account.alias : '',
    ];
  }).filter((order) => {
    if (!platformId) return true;
    const account = idx.accountById.get(order.account_id);
    return account ? account.platform_id === platformId : false;
  });

  filtered.sort((a, b) => (Number(b.ordered_at) || 0) - (Number(a.ordered_at) || 0));
  const rows = filtered.map((order) => {
    const account = idx.accountById.get(order.account_id);
    const platform = platformOfAccount(idx, account);
    const product = order.product_id ? idx.productById.get(order.product_id) : null;
    const amount = Number(order.amount) || 0;
    const cost = Number(order.cost) || 0;
    const profit = amount - cost;
    return [
      fmtDate(order.ordered_at),
      order.title || '—',
      platform ? platform.name : '—',
      account ? account.alias : '—',
      { html: `<span class="money">${money(amount)}</span>`, text: amount.toFixed(2) },
      { html: money(cost), text: cost.toFixed(2) },
      {
        html: `<span style="color:${profit >= 0 ? '#02743b' : '#dc2626'};font-weight:600">${money(profit)}</span>`,
        text: profit.toFixed(2),
      },
      ORDER_ROUTE[order.route] || order.route || '—',
      order.tracking_no || '待补',
      order.platform_order_no || '—',
      product ? product.name : '—',
      order.address_text || '—',
    ];
  });

  $('orders-count').textContent = `共 ${rows.length} 笔`;
  $('orders-table').innerHTML = rows.length
    ? tableHtml(
        ['下单时间', '商品标题', '平台', '账号', '金额', '成本', '利润', '履约', '物流单号', '平台单号', '关联商品', '收件地址'],
        rows,
        [4, 5, 6],
      )
    : '<div class="empty-inline">没有匹配的订单</div>';
  return rows;
}

/**
 * 渲染包裹页签。
 * @param {object} t 业务表
 * @returns {Array} 当前筛选后的包裹明细
 */
function renderParcelsTab(t) {
  const idx = buildIndexes(t);
  const status = $('parcels-status').value;
  const orderById = new Map(t.orders.map((o) => [o.id, o]));
  const filtered = searchList(t.parcels, $('parcels-search').value, (parcel) => {
    const account = parcel.account_id ? idx.accountById.get(parcel.account_id) : null;
    return [parcel.tracking_no, parcel.carrier, parcel.note, parcel.address_text, account ? account.alias : ''];
  })
    .filter((parcel) => (status ? (parcel.status || 'pending') === status : true))
    .sort((a, b) => (Number(b.scanned_at) || 0) - (Number(a.scanned_at) || 0));

  const rows = filtered.map((parcel) => {
    const account = parcel.account_id ? idx.accountById.get(parcel.account_id) : null;
    const platform = platformOfAccount(idx, account);
    const order = parcel.order_id ? orderById.get(parcel.order_id) : null;
    return [
      parcel.tracking_no,
      parcel.carrier || '未知快递',
      PARCEL_STATUS[parcel.status] || parcel.status || '—',
      PARCEL_SOURCE[parcel.source] || parcel.source || '—',
      fmtDate(parcel.scanned_at),
      platform ? platform.name : '—',
      account ? account.alias : '—',
      order ? order.title || order.platform_order_no || '已关联' : '—',
      parcel.note || '—',
    ];
  });

  $('parcels-count').textContent = `共 ${rows.length} 件`;
  $('parcels-table').innerHTML = rows.length
    ? tableHtml(['运单号', '快递公司', '状态', '来源', '入库时间', '平台', '账号', '关联订单', '备注'], rows)
    : '<div class="empty-inline">没有匹配的包裹</div>';
  return rows;
}

/**
 * 渲染转寄页签。
 * @param {object} t 业务表
 * @returns {Array} 当前筛选后的转寄批次明细
 */
function renderShipmentsTab(t) {
  const counts = parcelCountByShipment(t.parcels);
  const orderIds = new Set(t.orders.map((o) => o.id));
  const orderSets = new Map();
  for (const parcel of t.parcels) {
    if (!parcel.shipment_id || !parcel.order_id) continue;
    if (!orderIds.has(parcel.order_id)) continue;
    if (!orderSets.has(parcel.shipment_id)) orderSets.set(parcel.shipment_id, new Set());
    orderSets.get(parcel.shipment_id).add(parcel.order_id);
  }
  const orderCount = (id) => (orderSets.get(id) || new Set()).size;
  const filtered = searchList(t.shipments, $('shipments-search').value, (shipment) => [
    shipment.carrier,
    shipment.tracking_no,
    shipment.note,
  ]).sort((a, b) => (Number(b.shipped_at) || 0) - (Number(a.shipped_at) || 0));

  const rows = filtered.map((shipment) => {
    const fee = Number(shipment.fee) || 0;
    return [
      fmtDate(shipment.shipped_at, false),
      shipment.carrier || '—',
      shipment.tracking_no || '—',
      count(counts.get(shipment.id) || 0),
      count(orderCount(shipment.id)),
      { html: money(fee), text: fee.toFixed(2) },
      shipment.note || '—',
    ];
  });

  $('shipments-count').textContent = `共 ${rows.length} 批`;
  $('shipments-table').innerHTML = rows.length
    ? tableHtml(
      ['寄出日期', '快递公司', '运单号', '包裹数', '关联订单', '快递费', '备注'],
      rows,
      [3, 4, 5],
    )
    : '<div class="empty-inline">没有匹配的转寄批次</div>';
  return rows;
}

/**
 * 渲染账号页签。
 * @param {object} t 业务表
 * @returns {Array} 当前筛选后的账号明细
 */
function renderAccountsTab(t) {
  const idx = buildIndexes(t);
  const platformId = $('accounts-platform').value;
  const filtered = searchList(t.accounts, $('accounts-search').value, (account) => [
    account.alias,
    account.note,
  ]).filter((account) => (platformId ? account.platform_id === platformId : true));

  const rows = filtered.map((account) => {
    const platform = platformOfAccount(idx, account);
    return [
      platform ? platform.name : '—',
      account.alias,
      account.status === 'disabled' ? '停用' : '正常',
      account.note || '—',
      fmtDate(account.created_at),
    ];
  });

  $('accounts-count').textContent = `共 ${rows.length} 个`;
  $('accounts-table').innerHTML = rows.length
    ? tableHtml(['平台', '账号别名', '状态', '备注', '创建时间'], rows)
    : '<div class="empty-inline">没有匹配的账号</div>';
  return rows;
}

/**
 * 渲染平台页签。
 * @param {object} t 业务表
 * @returns {Array} 当前筛选后的平台明细
 */
function renderPlatformsTab(t) {
  const rows = searchList(t.platforms, $('platforms-search').value, (platform) => [platform.name]).map(
    (platform) => {
      const accounts = t.accounts.filter((a) => a.platform_id === platform.id);
      const accountIds = new Set(accounts.map((a) => a.id));
      const orderCount = t.orders.filter((o) => accountIds.has(o.account_id)).length;
      return [
        platform.name,
        count(accounts.length),
        count(orderCount),
        count(platform.sort),
        fmtDate(platform.created_at),
      ];
    },
  );

  $('platforms-count').textContent = `共 ${rows.length} 个`;
  $('platforms-table').innerHTML = rows.length
    ? tableHtml(['平台', '账号数', '订单数', '排序', '创建时间'], rows, [1, 2, 3])
    : '<div class="empty-inline">没有匹配的平台</div>';
  return rows;
}

/**
 * 渲染商品页签。
 * @param {object} t 业务表
 * @returns {Array} 当前筛选后的商品明细
 */
function renderProductsTab(t) {
  const rows = searchList(t.products, $('products-search').value, (product) => [
    product.name,
    product.spec,
    product.note,
  ]).map((product) => {
    const cost = Number(product.cost) || 0;
    const price = Number(product.price) || 0;
    return [
      product.name,
      product.spec || '—',
      { html: product.cost == null ? '—' : money(cost), text: product.cost == null ? '' : cost.toFixed(2) },
      { html: product.price == null ? '—' : money(price), text: product.price == null ? '' : price.toFixed(2) },
      {
        html: `<span style="color:${price - cost >= 0 ? '#02743b' : '#dc2626'};font-weight:600">${money(price - cost)}</span>`,
        text: (price - cost).toFixed(2),
      },
      product.note || '—',
      fmtDate(product.created_at),
    ];
  });

  $('products-count').textContent = `共 ${rows.length} 个`;
  $('products-table').innerHTML = rows.length
    ? tableHtml(['商品名称', '规格', '成本', '售价', '单件利润', '备注', '创建时间'], rows, [2, 3, 4])
    : '<div class="empty-inline">没有匹配的商品</div>';
  return rows;
}

/**
 * 渲染审计页签。
 * @param {object} t 业务表
 * @returns {Array} 当前筛选后的审计明细
 */
function renderAuditTab(t) {
  const rows = searchList(t.audit_logs, $('audit-search').value, (log) => [
    AUDIT_ACTION[log.action] || log.action,
    log.target_type,
    log.target_id,
    log.detail,
  ])
    .slice()
    .sort((a, b) => (Number(b.ts) || 0) - (Number(a.ts) || 0))
    .map((log) => [
      fmtDate(log.ts),
      AUDIT_ACTION[log.action] || log.action,
      log.target_type || '—',
      log.target_id || '—',
      log.detail || '—',
    ]);

  $('audit-count').textContent = `共 ${rows.length} 条`;
  $('audit-table').innerHTML = rows.length
    ? tableHtml(['时间', '动作', '对象类型', '对象 ID', '详情'], rows)
    : '<div class="empty-inline">暂无审计记录</div>';
  return rows;
}

/**
 * 平台下拉框选项（含“全部平台”）。
 * @param {string} selectId 下拉框 id
 * @param {Array} platforms 平台列表
 */
function fillPlatformSelect(selectId, platforms) {
  const select = $(selectId);
  const current = select.value;
  select.innerHTML =
    '<option value="">全部平台</option>' +
    platforms
      .map((p) => `<option value="${esc(p.id)}">${esc(p.name)}</option>`)
      .join('');
  select.value = platforms.some((p) => p.id === current) ? current : '';
}

/** 切换页签并渲染。 */
function renderTab() {
  for (const tab of TABS) {
    $(`panel-${tab}`).hidden = tab !== state.tab;
  }
  for (const node of $('tabs').querySelectorAll('button')) {
    node.classList.toggle('active', node.dataset.tab === state.tab);
  }
  if (!state.dataset) return;
  if (state.tab === 'overview') {
    renderOverview();
    return;
  }
  const t = tables();
  const renderers = {
    orders: renderOrdersTab,
    parcels: renderParcelsTab,
    shipments: renderShipmentsTab,
    accounts: renderAccountsTab,
    platforms: renderPlatformsTab,
    products: renderProductsTab,
    audit: renderAuditTab,
  };
  lastRows[state.tab] = renderers[state.tab](t);
}

/** 根据是否有数据切换空态与报表。 */
function renderAll() {
  const has = Boolean(state.dataset);
  $('empty').hidden = has;
  $('report').hidden = !has;
  $('btn-clear').disabled = !has;
  $('btn-export-summary').disabled = !has;
  if (!has) return;
  const t = tables();
  renderMeta(t);
  fillPlatformSelect('orders-platform', t.platforms);
  fillPlatformSelect('accounts-platform', t.platforms);
  renderTab();
}

/**
 * 处理用户选择的 JSON 文件。
 * @param {FileList|File[]} files 文件列表
 * @returns {Promise<void>}
 */
async function handleFiles(files) {
  const file = files && files[0];
  if (!file) return;
  if (!/\.json$/i.test(file.name)) {
    toast('请选择 App 导出的 JSON 文件');
    return;
  }
  let payload;
  try {
    payload = JSON.parse(await file.text());
  } catch (error) {
    toast('JSON 解析失败，请确认文件完整');
    return;
  }
  if (!payload || payload.app !== 'packkeeper' || !payload.data) {
    toast('这不是包裹管家导出的备份文件');
    return;
  }
  if (state.dataset) {
    const ok = window.confirm(
      `当前已有来自「${state.dataset.fileName}」的数据，导入会覆盖它，是否继续？`,
    );
    if (!ok) return;
  }
  const dataset = { fileName: file.name, importedAt: Date.now(), payload };
  try {
    await saveDataset(dataset);
  } catch (error) {
    toast('保存到本机失败：' + error);
    return;
  }
  state.dataset = dataset;
  renderAll();
  const orders = tables().orders.length;
  toast(`已导入 ${orders} 笔订单，数据已保存在本机`);
}

/**
 * CSV 单元格转义。
 * @param {*} value 原始值
 * @returns {string} CSV 安全文本
 */
function csvCell(value) {
  const raw = value && typeof value === 'object' ? value.text : value;
  const text = raw == null ? '' : String(raw);
  return /[",\r\n]/.test(text) ? `"${text.replace(/"/g, '""')}"` : text;
}

/**
 * 生成带 UTF-8 BOM 的 CSV 内容，便于 Excel 正确识别中文。
 * @param {string[]} headers 表头
 * @param {Array<Array<*>>} rows 行数据
 * @returns {string} CSV 文本
 */
function toCsv(headers, rows) {
  return '\uFEFF' + [headers, ...rows].map((row) => row.map(csvCell).join(',')).join('\r\n');
}

/**
 * 触发浏览器下载。
 * @param {string} fileName 文件名
 * @param {string} content 文件内容
 */
function download(fileName, content) {
  const blob = new Blob([content], { type: 'text/csv;charset=utf-8' });
  const url = URL.createObjectURL(blob);
  const link = document.createElement('a');
  link.href = url;
  link.download = fileName;
  document.body.appendChild(link);
  link.click();
  link.remove();
  setTimeout(() => URL.revokeObjectURL(url), 4000);
}

/** 各页签导出配置：表头与文件名。 */
const EXPORT_CONFIG = {
  orders: {
    name: '订单明细',
    headers: ['下单时间', '商品标题', '平台', '账号', '金额', '成本', '利润', '履约', '物流单号', '平台单号', '关联商品', '收件地址'],
  },
  parcels: {
    name: '包裹明细',
    headers: ['运单号', '快递公司', '状态', '来源', '入库时间', '平台', '账号', '关联订单', '备注'],
  },
  shipments: {
    name: '转寄批次',
    headers: ['寄出日期', '快递公司', '运单号', '包裹数', '关联订单', '快递费', '备注'],
  },
  accounts: {
    name: '账号台账',
    headers: ['平台', '账号别名', '状态', '备注', '创建时间'],
  },
  platforms: {
    name: '平台列表',
    headers: ['平台', '账号数', '订单数', '排序', '创建时间'],
  },
  products: {
    name: '商品列表',
    headers: ['商品名称', '规格', '成本', '售价', '单件利润', '备注', '创建时间'],
  },
  audit: {
    name: '审计日志',
    headers: ['时间', '动作', '对象类型', '对象 ID', '详情'],
  },
};

/**
 * 导出当前页签的筛选结果。
 * @param {string} tab 页签 id
 */
function exportTab(tab) {
  if (!state.dataset) return;
  const config = EXPORT_CONFIG[tab];
  if (!config) return;
  const rows = lastRows[tab] || [];
  if (rows.length === 0) {
    toast('当前筛选结果为空，没有可导出的数据');
    return;
  }
  download(`${config.name}-${stamp()}.csv`, toCsv(config.headers, rows));
  toast(`已导出 ${rows.length} 条${config.name}`);
}

/** 导出平台/账号汇总 CSV（全部数据 + 合计）。 */
function exportSummary() {
  const t = tables();
  if (!state.dataset) return;
  const idx = buildIndexes(t);
  const platformOf = (order) => {
    const platform = platformOfOrder(idx, order);
    return platform ? platform.name : '未关联账号';
  };
  const accountOf = (order) => {
    const account = idx.accountById.get(order.account_id);
    return account ? account.alias : '未关联账号';
  };

  const rows = [];
  const platformGroups = groupOrders(t.orders, platformOf);
  for (const [name, s] of [...platformGroups.entries()].sort((a, b) => b[1].sales - a[1].sales)) {
    rows.push([
      '平台汇总', name, s.orderCount, s.sales.toFixed(2), s.cost.toFixed(2), s.profit.toFixed(2), '', '',
    ]);
  }
  const accountGroups = groupOrders(t.orders, accountOf);
  for (const [name, s] of [...accountGroups.entries()].sort((a, b) => b[1].sales - a[1].sales)) {
    rows.push([
      '账号汇总', name, s.orderCount, s.sales.toFixed(2), s.cost.toFixed(2), s.profit.toFixed(2), '', '',
    ]);
  }
  const total = sumOrders(t.orders);
  const ship = sumShipments(t.shipments);
  const netProfit = total.profit - ship.fee;
  rows.push([
    '合计', '', total.orderCount, total.sales.toFixed(2), total.cost.toFixed(2),
    total.profit.toFixed(2), ship.fee.toFixed(2), netProfit.toFixed(2),
  ]);

  const headers = ['维度', '名称', '订单数', '销售额', '成本', '毛利', '快递费', '净利润'];
  download(`经营汇总-${stamp()}.csv`, toCsv(headers, rows));
  toast('已导出经营汇总');
}

/** 绑定搜索与筛选变化，实时重绘当前页签。 */
function bindFilters() {
  const map = {
    orders: ['orders-search', 'orders-platform'],
    parcels: ['parcels-search', 'parcels-status'],
    shipments: ['shipments-search'],
    accounts: ['accounts-search', 'accounts-platform'],
    platforms: ['platforms-search'],
    products: ['products-search'],
    audit: ['audit-search'],
  };
  for (const [tab, ids] of Object.entries(map)) {
    for (const id of ids) {
      const node = $(id);
      node.addEventListener('input', () => {
        if (state.tab === tab) renderTab();
      });
      node.addEventListener('change', () => {
        if (state.tab === tab) renderTab();
      });
    }
  }
}

/** 绑定页面交互。 */
function bindEvents() {
  const fileInput = $('file-input');
  const openPicker = () => fileInput.click();
  $('btn-import').addEventListener('click', openPicker);
  $('btn-import-empty').addEventListener('click', (event) => {
    event.stopPropagation();
    openPicker();
  });
  fileInput.addEventListener('change', () => {
    handleFiles(fileInput.files);
    fileInput.value = '';
  });

  const dropZone = $('drop-zone');
  dropZone.addEventListener('click', openPicker);
  dropZone.addEventListener('dragover', (event) => {
    event.preventDefault();
    dropZone.classList.add('dragover');
  });
  dropZone.addEventListener('dragleave', () => dropZone.classList.remove('dragover'));
  dropZone.addEventListener('drop', (event) => {
    event.preventDefault();
    dropZone.classList.remove('dragover');
    handleFiles(event.dataTransfer.files);
  });
  document.addEventListener('dragover', (event) => event.preventDefault());
  document.addEventListener('drop', (event) => {
    if (event.target.closest('#drop-zone')) return;
    event.preventDefault();
    handleFiles(event.dataTransfer.files);
  });

  $('tabs').addEventListener('click', (event) => {
    const button = event.target.closest('button[data-tab]');
    if (!button || button.dataset.tab === state.tab) return;
    state.tab = button.dataset.tab;
    renderTab();
  });

  $('range-group').addEventListener('click', (event) => {
    const button = event.target.closest('button[data-range]');
    if (!button) return;
    const range = button.dataset.range;
    if (range === state.range) return;
    state.range = range;
    for (const node of $('range-group').querySelectorAll('button')) {
      node.classList.toggle('active', node === button);
    }
    renderOverview();
  });

  $('btn-export-summary').addEventListener('click', exportSummary);
  for (const tab of Object.keys(EXPORT_CONFIG)) {
    $(`${tab}-export`).addEventListener('click', () => exportTab(tab));
  }
  bindFilters();

  $('btn-clear').addEventListener('click', async () => {
    if (!state.dataset) return;
    if (!window.confirm('清空后本机保存的导入数据会被删除，确定继续？')) return;
    await clearDataset();
    state.dataset = null;
    renderAll();
    toast('已清空本机数据');
  });
}

/** 页面初始化：恢复上次导入的数据并渲染。 */
async function init() {
  bindEvents();
  try {
    const dataset = await loadDataset();
    if (dataset && dataset.payload) {
      state.dataset = dataset;
      renderAll();
    }
  } catch (error) {
    console.error(error);
    toast('读取本机数据失败，可重新导入 JSON');
  }
}

document.addEventListener('DOMContentLoaded', init);
