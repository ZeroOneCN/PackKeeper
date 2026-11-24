'use strict';

/** IndexedDB 数据库名。 */
const DB_NAME = 'packkeeper-report';
/** 对象仓库名。 */
const STORE_NAME = 'datasets';
/** 固定主键：只保留最近一次导入。 */
const DATASET_KEY = 'latest';

/** 包裹状态中文名。 */
const PARCEL_STATUS = { pending: '待认领', assigned: '已分配', exception: '异常件' };
/** 包裹来源中文名。 */
const PARCEL_SOURCE = { scan: '扫码', ocr: '面单', manual: '手动' };
/** 订单状态中文名。 */
const ORDER_STATUS = { created: '已建单' };
/** 履约路径中文名。 */
const ORDER_ROUTE = { warehouse: '仓库', direct: '直送' };

/** 页面状态。 */
const state = { dataset: null, range: 'all' };

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
 *   scan_events:Array,audit_logs:Array}} 业务表集合
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
            const value = cell && typeof cell === 'object' && 'html' in cell ? cell.html : esc(cell);
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

/** 渲染数据概要。 */
function renderMeta(t) {
  const payload = state.dataset.payload;
  const parts = [
    `<span>数据文件：<strong>${esc(state.dataset.fileName)}</strong></span>`,
    `<span>导入时间：<strong>${esc(fmtDate(state.dataset.importedAt))}</strong></span>`,
    `<span>备份时间：<strong>${esc(fmtDate(payload.exported_at))}</strong></span>`,
    `<span>平台 ${t.platforms.length} · 账号 ${t.accounts.length} · 商品 ${t.products.length} · 订单 ${t.orders.length} · 包裹 ${t.parcels.length}</span>`,
  ];
  $('meta').innerHTML = parts.join('');
}

/** 渲染 KPI 指标卡。 */
function renderKpis(t, orders) {
  const sum = sumOrders(orders);
  const pendingParcels = t.parcels.filter((p) => p.status === 'pending').length;
  const pendingOrders = t.orders.filter((o) => !o.tracking_no).length;
  const avg = sum.orderCount > 0 ? sum.sales / sum.orderCount : 0;
  const margin = sum.sales > 0 ? (sum.profit / sum.sales) * 100 : 0;

  const cards = [
    { label: '订单数', value: count(sum.orderCount), sub: '笔' },
    { label: '销售额', value: money(sum.sales), sub: RANGE_LABEL[state.range] },
    { label: '成本', value: money(sum.cost), sub: '已录成本的订单' },
    {
      label: '利润',
      value: money(sum.profit),
      sub: sum.sales > 0 ? `利润率 ${margin.toFixed(1)}%` : '暂无销售额',
      tone: 'green',
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
    const account = idx.accountById.get(order.account_id);
    const platform = account ? idx.platformById.get(account.platform_id) : null;
    return platform ? platform.name : '未关联账号';
  };
  const accountOf = (order) => {
    const account = idx.accountById.get(order.account_id);
    return account ? `${account.alias}（${account.owner || '未填写归属'}）` : '未关联账号';
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
    ? tableHtml(['平台', '订单数', '销售额', '成本', '利润'], platformRows, [1, 2, 3, 4])
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
    ? tableHtml(['账号', '订单数', '销售额', '成本', '利润'], accountRows, [1, 2, 3, 4])
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
    const platform = account ? idx.platformById.get(account.platform_id) : null;
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

/** 渲染整个报表。 */
function renderReport() {
  const t = tables();
  const start = rangeStart(state.range);
  const orders = start == null
    ? t.orders
    : t.orders.filter((o) => (Number(o.ordered_at) || 0) >= start);

  renderMeta(t);
  $('range-hint').textContent = `${RANGE_LABEL[state.range]} · ${orders.length} 笔订单`;
  renderKpis(t, orders);
  renderBreakdowns(t, orders);
  renderTrend(t);
  renderParcels(t);
  renderPending(t);
}

/** 根据是否有数据切换空态与报表。 */
function renderAll() {
  const has = Boolean(state.dataset);
  $('empty').hidden = has;
  $('report').hidden = !has;
  for (const id of ['btn-export-orders', 'btn-export-parcels', 'btn-export-summary', 'btn-clear']) {
    $(id).disabled = !has;
  }
  if (has) renderReport();
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
  const text = value == null ? '' : String(value);
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

/** 导出订单明细 CSV（全部订单，按时间倒序）。 */
function exportOrders() {
  const t = tables();
  if (!state.dataset) return;
  const idx = buildIndexes(t);
  const rows = [...t.orders]
    .sort((a, b) => (Number(b.ordered_at) || 0) - (Number(a.ordered_at) || 0))
    .map((order) => {
      const account = idx.accountById.get(order.account_id);
      const platform = account ? idx.platformById.get(account.platform_id) : null;
      const product = order.product_id ? idx.productById.get(order.product_id) : null;
      const amount = Number(order.amount) || 0;
      const cost = Number(order.cost) || 0;
      return [
        order.id,
        platform ? platform.name : '',
        account ? account.alias : '',
        order.title || '',
        product ? product.name : '',
        amount,
        cost,
        amount - cost,
        ORDER_ROUTE[order.route] || order.route || '',
        order.tracking_no || '',
        ORDER_STATUS[order.status] || order.status || '',
        fmtDate(order.ordered_at),
        order.platform_order_no || '',
        order.address_text || '',
      ];
    });
  const headers = [
    '订单ID', '平台', '账号', '商品标题', '关联商品', '金额', '成本', '利润',
    '履约路径', '物流单号', '状态', '下单时间', '平台单号', '收件地址',
  ];
  download(`订单明细-${stamp()}.csv`, toCsv(headers, rows));
  toast(`已导出 ${rows.length} 笔订单`);
}

/** 导出包裹明细 CSV（按入库时间倒序）。 */
function exportParcels() {
  const t = tables();
  if (!state.dataset) return;
  const idx = buildIndexes(t);
  const orderById = new Map(t.orders.map((o) => [o.id, o]));
  const rows = [...t.parcels]
    .sort((a, b) => (Number(b.scanned_at) || 0) - (Number(a.scanned_at) || 0))
    .map((parcel) => {
      const account = parcel.account_id ? idx.accountById.get(parcel.account_id) : null;
      const platform = account ? idx.platformById.get(account.platform_id) : null;
      const order = parcel.order_id ? orderById.get(parcel.order_id) : null;
      return [
        parcel.tracking_no,
        parcel.carrier || '',
        PARCEL_STATUS[parcel.status] || parcel.status || '',
        PARCEL_SOURCE[parcel.source] || parcel.source || '',
        fmtDate(parcel.scanned_at),
        account ? `${platform ? platform.name + ' · ' : ''}${account.alias}` : '',
        order ? order.title || '' : '',
        parcel.note || '',
      ];
    });
  const headers = ['运单号', '快递公司', '状态', '来源', '入库时间', '归属账号', '关联订单', '备注'];
  download(`包裹明细-${stamp()}.csv`, toCsv(headers, rows));
  toast(`已导出 ${rows.length} 个包裹`);
}

/** 导出平台/账号汇总 CSV（全部数据 + 合计）。 */
function exportSummary() {
  const t = tables();
  if (!state.dataset) return;
  const idx = buildIndexes(t);
  const platformOf = (order) => {
    const account = idx.accountById.get(order.account_id);
    const platform = account ? idx.platformById.get(account.platform_id) : null;
    return platform ? platform.name : '未关联账号';
  };
  const accountOf = (order) => {
    const account = idx.accountById.get(order.account_id);
    return account ? `${account.alias}（${account.owner || '未填写归属'}）` : '未关联账号';
  };

  const rows = [];
  const platformGroups = groupOrders(t.orders, platformOf);
  for (const [name, s] of [...platformGroups.entries()].sort((a, b) => b[1].sales - a[1].sales)) {
    rows.push(['平台汇总', name, s.orderCount, s.sales.toFixed(2), s.cost.toFixed(2), s.profit.toFixed(2)]);
  }
  const accountGroups = groupOrders(t.orders, accountOf);
  for (const [name, s] of [...accountGroups.entries()].sort((a, b) => b[1].sales - a[1].sales)) {
    rows.push(['账号汇总', name, s.orderCount, s.sales.toFixed(2), s.cost.toFixed(2), s.profit.toFixed(2)]);
  }
  const total = sumOrders(t.orders);
  rows.push(['合计', '', total.orderCount, total.sales.toFixed(2), total.cost.toFixed(2), total.profit.toFixed(2)]);

  const headers = ['维度', '名称', '订单数', '销售额', '成本', '利润'];
  download(`经营汇总-${stamp()}.csv`, toCsv(headers, rows));
  toast('已导出经营汇总');
}

/** 生成文件名用的时间戳。 */
function stamp() {
  const d = new Date();
  const pad = (n) => String(n).padStart(2, '0');
  return `${d.getFullYear()}${pad(d.getMonth() + 1)}${pad(d.getDate())}-${pad(d.getHours())}${pad(d.getMinutes())}`;
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

  $('range-group').addEventListener('click', (event) => {
    const button = event.target.closest('button[data-range]');
    if (!button) return;
    const range = button.dataset.range;
    if (range === state.range) return;
    state.range = range;
    for (const node of $('range-group').querySelectorAll('button')) {
      node.classList.toggle('active', node === button);
    }
    renderReport();
  });

  $('btn-export-orders').addEventListener('click', exportOrders);
  $('btn-export-parcels').addEventListener('click', exportParcels);
  $('btn-export-summary').addEventListener('click', exportSummary);

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
