package metis.gateway.runtime

public func gatewayBuildControlUiCronScript(): String {
    """

  function cronEsc(s) {
    if (s === null || s === undefined) { return ''; }
    return String(s)
      .replace(new RegExp('&', 'g'), '&amp;')
      .replace(new RegExp('<', 'g'), '&lt;')
      .replace(new RegExp('>', 'g'), '&gt;')
      .replace(new RegExp('"', 'g'), '&quot;')
      .replace(new RegExp('\\u0027', 'g'), '&#39;');
  }

  function cronAttr(s) {
    if (s === null || s === undefined) { return ''; }
    return String(s)
      .replace(new RegExp('&', 'g'), '&amp;')
      .replace(new RegExp('<', 'g'), '&lt;')
      .replace(new RegExp('"', 'g'), '&quot;')
      .replace(new RegExp('\\r', 'g'), ' ')
      .replace(new RegExp('\\n', 'g'), ' ');
  }

  function cronSchedLabel(j) {
    if (!j || !j.schedule) { return ''; }
    var sch = j.schedule;
    var sk = String(sch.kind || '').toLowerCase();
    if (sk === 'at') {
      var atMs = Number(sch.atMs || 0);
      if (!Number.isFinite(atMs) || atMs <= 0) { return 'at'; }
      var d = new Date(atMs);
      return Number.isFinite(d.getTime()) ? d.toLocaleString() : String(sch.atMs);
    }
    if (sk === 'cron') {
      var ex = String(sch.cronExpr || '').trim();
      var tz = String(sch.timeZone || 'UTC').trim();
      return ex ? (ex + ' · ' + tz) : 'cron';
    }
    var em = Number(sch.everyMs || 0);
    if (em <= 0) { return 'every'; }
    if (em % 86400000 === 0) { return (em / 86400000) + 'd'; }
    if (em % 3600000 === 0) { return (em / 3600000) + 'h'; }
    if (em % 60000 === 0) { return (em / 60000) + 'm'; }
    if (em % 1000 === 0) { return (em / 1000) + 's'; }
    return em + 'ms';
  }

  function cronRelUntilMs(nxt) {
    var n = Number(nxt || 0);
    if (!Number.isFinite(n) || n <= 0) { return '—'; }
    var now = Date.now();
    var d = n - now;
    if (d <= 0) { return '已到期'; }
    var sec = Math.floor(d / 1000);
    if (sec < 60) { return sec + 's'; }
    var min = Math.floor(sec / 60);
    if (min < 60) { return min + 'm'; }
    var hr = Math.floor(min / 60);
    if (hr < 48) { return hr + 'h'; }
    var day = Math.floor(hr / 24);
    return day + 'd';
  }

  function cronRelAgoMs(lr) {
    var t = Number(lr || 0);
    if (!Number.isFinite(t) || t <= 0) { return '从未'; }
    var now = Date.now();
    var d = now - t;
    if (d < 0) { return '—'; }
    var sec = Math.floor(d / 1000);
    if (sec < 60) { return sec + 's 前'; }
    var min = Math.floor(sec / 60);
    if (min < 60) { return min + 'm 前'; }
    var hr = Math.floor(min / 60);
    if (hr < 48) { return hr + 'h 前'; }
    var day = Math.floor(hr / 24);
    return day + 'd 前';
  }

  function cronRunStatusInner(j) {
    if (!j || !j.state) { return '<span class="cron-badge--muted">未知</span>'; }
    var st = String(j.state.lastStatus || '').toLowerCase();
    if (st === 'success' || st === 'ok') {
      return '<span class="cron-badge--yes">成功</span>';
    }
    if (st === 'error') {
      return '<span class="cron-badge--no">错误</span>';
    }
    if (st === 'skipped') {
      return '<span class="cron-badge--muted">跳过</span>';
    }
    return '<span class="cron-badge--muted">—</span>';
  }

  function buildCronRunHistoryBlockHtml(cronData) {
    var meta = (cronData && cronData.runHistory) ? cronData.runHistory : {};
    var entries = Array.isArray(meta.entries) ? meta.entries.slice() : [];
    var totalStored = Number(meta.total || entries.length) || 0;
    var returned = Number(meta.returned || entries.length) || 0;

    var scope = String(v3CronRunScope || 'all');
    var scoped = entries.filter(function(e) {
      if (scope === 'all') { return true; }
      return String(e.jobId || '') === scope;
    });

    var q = String(v3CronRunSearch || '').trim().toLowerCase();
    var searched = !q ? scoped : scoped.filter(function(e) {
      var sum = String(e.summary || '');
      var blob = (String(e.jobId || '') + ' ' + sum + ' ' + String(e.status || '')).toLowerCase();
      return blob.indexOf(q) >= 0;
    });

    var stF = String(v3CronRunStatusFilter || 'all');
    var statusFiltered = searched.filter(function(e) {
      if (stF === 'all') { return true; }
      var s = String(e.status || '').toLowerCase();
      if (stF === 'ok') { return s === 'ok' || s === 'success'; }
      if (stF === 'error') { return s === 'error'; }
      if (stF === 'skipped') { return s === 'skipped'; }
      return true;
    });

    var dF = String(v3CronRunDeliveryFilter || 'all');
    var deliveryFiltered = statusFiltered.filter(function(e) {
      if (dF === 'all') { return true; }
      return String(e.deliveryStatus || 'not-requested') === dF;
    });

    var sorted = deliveryFiltered.slice();
    var sortKey = String(v3CronRunSort || 'newest');
    sorted.sort(function(a, b) {
      var ta = Number(a.ts || 0);
      var tb = Number(b.ts || 0);
      if (!Number.isFinite(ta)) { ta = 0; }
      if (!Number.isFinite(tb)) { tb = 0; }
      return sortKey === 'oldest' ? (ta - tb) : (tb - ta);
    });

    var DISPLAY_CAP = 500;
    var display = sorted.slice(0, DISPLAY_CAP);
    var countRight = '显示 ' + display.length + ' / 共 ' + sorted.length;
    if (totalStored > returned && totalStored > 0) {
      countRight += '（仓库共 ' + totalStored + ' 条，已加载 ' + returned + '）';
    } else if (sorted.length > DISPLAY_CAP) {
      countRight += '（仅展示前 ' + DISPLAY_CAP + ' 条）';
    }

    var jobs = (cronData && cronData.jobs) ? cronData.jobs : [];
    var scopeOpts = '<option value="all"' + (scope === 'all' ? ' selected' : '') + '>所有任务</option>';
    jobs.forEach(function(j) {
      var id = String(j.id || '');
      if (!id) { return; }
      scopeOpts += '<option value="' + id.replace(new RegExp('"', 'g'), '&quot;') + '"' + (scope === id ? ' selected' : '') + '>' + cronEsc(id) + '</option>';
    });

    var sortSel = String(v3CronRunSort || 'newest');
    var srch = String(v3CronRunSearch || '').replace(new RegExp('"', 'g'), '&quot;');

    var row1 =
      '<div class="cron-run-history__row cron-run-history__row--1">' +
        '<div class="cron-run-history__field cron-run-history__field--scope">' +
          '<label class="cron-run-history__lbl" for="cron-run-scope">范围</label>' +
          '<select id="cron-run-scope" class="cron-run-history__control">' + scopeOpts + '</select>' +
        '</div>' +
        '<div class="cron-run-history__field cron-run-history__field--search">' +
          '<label class="cron-run-history__lbl" for="cron-run-search">搜索运行</label>' +
          '<input type="text" id="cron-run-search" class="cron-run-history__control" placeholder="摘要、错误或任务" value="' + srch + '" />' +
        '</div>' +
        '<div class="cron-run-history__field cron-run-history__field--sort">' +
          '<label class="cron-run-history__lbl" for="cron-run-sort">排序</label>' +
          '<select id="cron-run-sort" class="cron-run-history__control">' +
            '<option value="newest"' + (sortSel === 'newest' ? ' selected' : '') + '>最新优先</option>' +
            '<option value="oldest"' + (sortSel === 'oldest' ? ' selected' : '') + '>最旧优先</option>' +
          '</select>' +
        '</div>' +
      '</div>';

    var stf = String(v3CronRunStatusFilter || 'all');
    var df = String(v3CronRunDeliveryFilter || 'all');
    var row2 =
      '<div class="cron-run-history__row cron-run-history__row--2">' +
        '<div class="cron-run-history__field cron-run-history__field--half">' +
          '<label class="cron-run-history__lbl" for="cron-run-status">状态</label>' +
          '<select id="cron-run-status" class="cron-run-history__control">' +
            '<option value="all"' + (stf === 'all' ? ' selected' : '') + '>全部状态</option>' +
            '<option value="ok"' + (stf === 'ok' ? ' selected' : '') + '>成功</option>' +
            '<option value="error"' + (stf === 'error' ? ' selected' : '') + '>错误</option>' +
            '<option value="skipped"' + (stf === 'skipped' ? ' selected' : '') + '>跳过</option>' +
          '</select>' +
        '</div>' +
        '<div class="cron-run-history__field cron-run-history__field--half">' +
          '<label class="cron-run-history__lbl" for="cron-run-delivery">投递</label>' +
          '<select id="cron-run-delivery" class="cron-run-history__control">' +
            '<option value="all"' + (df === 'all' ? ' selected' : '') + '>全部投递</option>' +
            '<option value="not-requested"' + (df === 'not-requested' ? ' selected' : '') + '>未请求</option>' +
            '<option value="delivered"' + (df === 'delivered' ? ' selected' : '') + '>已投递</option>' +
            '<option value="not-delivered"' + (df === 'not-delivered' ? ' selected' : '') + '>未投递</option>' +
            '<option value="unknown"' + (df === 'unknown' ? ' selected' : '') + '>未知</option>' +
          '</select>' +
        '</div>' +
      '</div>';

    var itemsHtml = '';
    if (!display.length) {
      itemsHtml = '<div class="cron-empty cron-run-history__empty">暂无运行记录（执行任务后将写入 <span class="mono">runs/*.jsonl</span>）。</div>';
    } else {
      itemsHtml = display.map(function(e) {
        var jid = String(e.jobId || '');
        var st = String(e.status || '').toLowerCase();
        var stLabel = (st === 'ok' || st === 'success') ? '成功' : (st === 'error' ? '错误' : (st === 'skipped' ? '跳过' : (st || '—')));
        var stBadge = (st === 'ok' || st === 'success')
          ? '<span class="cron-badge--yes cron-run-history__badge">' + stLabel + '</span>'
          : (st === 'error' ? '<span class="cron-badge--no cron-run-history__badge">' + stLabel + '</span>' : '<span class="cron-badge--muted cron-run-history__badge">' + stLabel + '</span>');
        var sum = String(e.summary || '').trim() || '（无摘要）';
        var ds = String(e.deliveryStatus || 'not-requested');
        var dlab = (ds === 'delivered') ? '已投递' : (ds === 'not-delivered') ? '未投递' : (ds === 'unknown') ? '未知' : '未请求';
        var ts = Number(e.ts || 0);
        var runAt = Number(e.runAtMs || ts);
        var dur = Number(e.durationMs || 0);
        var nxt = Number(e.nextRunAtMs || 0);
        var tsStr = (Number.isFinite(ts) && ts > 0) ? new Date(ts).toLocaleString() : '—';
        var runAtStr = (Number.isFinite(runAt) && runAt > 0) ? new Date(runAt).toLocaleString() : '—';
        var durStr = (Number.isFinite(dur) && dur >= 0) ? (dur + 'ms') : '—';
        var relNext = cronRelUntilMs(nxt);
        return '<div class="cron-run-history__item">' +
          '<div class="cron-run-history__item-main">' +
            '<div class="cron-run-history__item-title">' + cronEsc(jid) + ' · ' + stBadge + '</div>' +
            '<div class="cron-run-history__item-sum">' + cronEsc(sum.slice(0, 500)) + '</div>' +
            '<span class="cron-run-history__deliv-pill">' + cronEsc(dlab) + '</span>' +
          '</div>' +
          '<div class="cron-run-history__item-meta mono">' +
            '<div>' + cronEsc(tsStr) + '</div>' +
            '<div class="muted">运行于 ' + cronEsc(runAtStr) + '</div>' +
            '<div>' + cronEsc(durStr) + '</div>' +
            '<div class="muted">到期 ' + cronEsc(relNext) + '</div>' +
          '</div>' +
        '</div>';
      }).join('');
    }

    return (
      '<div class="cron-section__head cron-run-history__head">' +
        '<div>' +
          '<div class="cron-section__title">运行历史</div>' +
          '<div class="cron-section__sub">所有任务的最新运行记录。</div>' +
        '</div>' +
        '<div class="cron-run-history__count muted">' + countRight + '</div>' +
      '</div>' +
      row1 + row2 +
      '<div class="cron-run-history__list">' + itemsHtml + '</div>'
    );
  }

  function buildV3CronRenderState(cronData) {
    const rawCron = ((cronData && cronData.jobs) || []).slice();
    var cronAnyEnabled = false;
    var cronMinNext = null;
    for (var cix = 0; cix < rawCron.length; cix++) {
      var cjob = rawCron[cix];
      if (cjob && cjob.enabled) { cronAnyEnabled = true; }
      var cst = (cjob && cjob.state) ? cjob.state : {};
      var cnxt = Number(cst.nextRunAtMs || 0);
      if (cjob && cjob.enabled && cnxt > 0) {
        if (cronMinNext === null || cnxt < cronMinNext) { cronMinNext = cnxt; }
      }
    }
    const cfq = String(v3CronFilterText || '').trim().toLowerCase();
    var cronFiltered = rawCron.filter(function(j) {
      if (!j) { return false; }
      if (v3CronEnableFilter === 'enabled' && !j.enabled) { return false; }
      if (v3CronEnableFilter === 'disabled' && j.enabled) { return false; }
      var sk = (j.schedule && j.schedule.kind) ? String(j.schedule.kind).toLowerCase() : '';
      if (v3CronScheduleFilter === 'every' && sk !== 'every') { return false; }
      if (v3CronScheduleFilter === 'at' && sk !== 'at') { return false; }
      if (v3CronScheduleFilter === 'cron' && sk !== 'cron') { return false; }
      var last = Number((j.state && j.state.lastRunAtMs) || 0);
      if (v3CronLastRunFilter === 'never' && last > 0) { return false; }
      if (v3CronLastRunFilter === 'has' && last <= 0) { return false; }
      if (cfq) {
        var blob = (String(j.id || '') + ' ' + String(j.prompt || '') + ' ' + String(j.sessionTarget || '')).toLowerCase();
        if (blob.indexOf(cfq) < 0) { return false; }
      }
      return true;
    });
    const cdir = (v3CronSortDir === 'desc') ? -1 : 1;
    cronFiltered.sort(function(a, b) {
      if (v3CronSort === 'name') {
        var an = String(a.id || '').toLowerCase();
        var bn = String(b.id || '').toLowerCase();
        if (an < bn) { return -cdir; }
        if (an > bn) { return cdir; }
        return 0;
      }
      var ax = Number((a.state && a.state.nextRunAtMs) || 0);
      var bx = Number((b.state && b.state.nextRunAtMs) || 0);
      if (ax === bx) { return 0; }
      return (ax < bx ? -cdir : cdir);
    });

    var cronCardsHtml = cronFiltered.map(function(j) {
      var st = j.state || {};
      var nxt = Number(st.nextRunAtMs || 0);
      var lr = Number(st.lastRunAtMs || 0);
      var err = (st.lastError && String(st.lastError).trim()) ? String(st.lastError) : '';
      var jid = j.id || '';
      var toggleAct = j.enabled ? 'disable' : 'enable';
      var toggleLabel = j.enabled ? '禁用' : '启动';
      var cardCls = 'cron-task-card';
      if (v3CronSelectedId && v3CronSelectedId === jid) {
        cardCls += ' cron-task-card--selected';
      }
      var sk = (j.schedule && j.schedule.kind) ? String(j.schedule.kind).toLowerCase() : '';
      var kindPill = (sk === 'at') ? '一次性' : (sk === 'cron') ? 'cron' : '间隔';
      var promptBody = String(j.prompt || '').trim()
        ? cronEsc(j.prompt)
        : '<span class="muted">（无提示内容）</span>';
      var lastErrLine = (lr > 0 && err)
        ? '<div class="cron-task-card__lasterr muted">' + cronEsc(err.slice(0, 240)) + '</div>'
        : '';
      var ds = ' data-cron-id="' + cronAttr(jid) + '" data-cron-message="' + cronAttr(j.prompt || '') + '" data-cron-schedule-kind="' + cronAttr((j.schedule && j.schedule.kind) ? j.schedule.kind : '') + '" data-cron-every-ms="' + cronAttr((j.schedule && j.schedule.everyMs) ? String(j.schedule.everyMs) : '0') + '" data-cron-at-ms="' + cronAttr((j.schedule && j.schedule.atMs) ? String(j.schedule.atMs) : '0') + '" data-cron-expr="' + cronAttr((j.schedule && j.schedule.cronExpr) ? j.schedule.cronExpr : '') + '" data-cron-tz="' + cronAttr((j.schedule && j.schedule.timeZone) ? j.schedule.timeZone : 'UTC') + '" data-cron-session="' + cronAttr(j.sessionTarget || 'main') + '" data-cron-enabled="' + (j.enabled ? 'true' : 'false') + '"' +
        ' data-delivery-ch="' + cronAttr(j.deliveryChannel || '') + '" data-delivery-to="' + cronAttr(j.deliveryTo || '') + '" data-delivery-ann="' + (j.deliveryAnnounce ? 'true' : 'false') + '"' +
        ' data-system-event="' + cronAttr(j.systemEvent || '') + '" data-wake-mode="' + cronAttr(j.wakeMode || '') + '"';
      var sep = '<span class="cron-task-action-sep" aria-hidden="true"></span>';
      var toggleCls = 'cron-task-action cron-task-action--toggle ' + (j.enabled ? 'cron-task-action--toggle-on' : 'cron-task-action--toggle-off');
      return '<article class="' + cardCls + '" ' + ds + '>' +
        '<div class="cron-task-card__head">' +
          '<div class="cron-task-card__title-block">' +
            '<div class="cron-task-card__name">' + cronEsc(jid) + '</div>' +
            '<div class="cron-task-card__cron mono">Cron · ' + cronEsc(cronSchedLabel(j)) + '</div>' +
          '</div>' +
          '<div class="cron-task-card__meta">' +
            '<div class="cron-task-card__stat"><span class="cron-task-stat__lbl">状态</span>' + cronRunStatusInner(j) + '</div>' +
            '<div class="cron-task-card__stat"><span class="cron-task-stat__lbl">下次</span><span class="mono cron-task-stat__mono">' + cronEsc(cronRelUntilMs(nxt)) + '</span></div>' +
            '<div class="cron-task-card__stat"><span class="cron-task-stat__lbl">上次</span><span class="mono cron-task-stat__mono">' + cronEsc(cronRelAgoMs(lr)) + '</span></div>' +
          '</div>' +
        '</div>' +
        '<div class="cron-task-card__prompt">' +
          '<div class="cron-task-card__prompt-label">任务描述</div>' +
          '<div class="cron-task-card__prompt-body">' + promptBody + '</div>' +
          lastErrLine +
        '</div>' +
        '<div class="cron-task-card__footer">' +
          '<div class="cron-task-card__badges">' +
            (j.enabled ? '<span class="cron-pill cron-pill--ok">已启用</span>' : '<span class="cron-pill cron-pill--off">已禁用</span>') +
            '<span class="cron-pill">' + cronEsc(j.sessionTarget || 'main') + '</span>' +
            '<span class="cron-pill cron-pill--muted">' + cronEsc(kindPill) + '</span>' +
          '</div>' +
          '<div class="cron-task-card__actions" role="toolbar" aria-label="任务操作">' +
            '<button type="button" class="cron-task-action" data-cron-action="edit" data-cron-id="' + cronAttr(jid) + '"' + ds + '>编辑</button>' + sep +
            '<button type="button" class="cron-task-action" data-cron-action="clone" data-cron-id="' + cronAttr(jid) + '"' + ds + '>克隆</button>' + sep +
            '<button type="button" class="' + toggleCls + '" data-cron-action="' + toggleAct + '" data-cron-id="' + cronAttr(jid) + '">' + toggleLabel + '</button>' + sep +
            '<button type="button" class="cron-task-action" data-cron-action="run_once" data-cron-id="' + cronAttr(jid) + '">运行</button>' + sep +
            '<button type="button" class="cron-task-action" disabled title="控制面板暂未接入">到期运行</button>' + sep +
            '<button type="button" class="cron-task-action" data-cron-action="focus_run_history" data-cron-id="' + cronAttr(jid) + '">历史</button>' + sep +
            '<button type="button" class="cron-task-action cron-task-action--danger" data-cron-action="remove" data-cron-id="' + cronAttr(jid) + '">删除</button>' +
          '</div>' +
        '</div>' +
      '</article>';
    }).join('');
    if (!cronCardsHtml) {
      cronCardsHtml = '<div class="cron-empty">没有匹配的任务</div>';
    }

    return {
      cronAnyEnabled: cronAnyEnabled,
      cronCount: rawCron.length,
      cronMinNext: cronMinNext,
      cronStorePath: cronEsc((cronData && cronData.storePath) || ''),
      cronCardsHtml: cronCardsHtml,
      cronRunHistoryBlockHtml: buildCronRunHistoryBlockHtml(cronData)
    };
  }

  function cronMsToDatetimeLocal(ms) {
    var d = new Date(Number(ms));
    if (!Number.isFinite(d.getTime())) return '';
    var pad = function(n) { return n < 10 ? '0' + n : '' + n; };
    return d.getFullYear() + '-' + pad(d.getMonth() + 1) + '-' + pad(d.getDate()) + 'T' + pad(d.getHours()) + ':' + pad(d.getMinutes());
  }

  function cronEveryMsToForm(everyMs) {
    var m = Number(everyMs) || 0;
    if (m <= 0) return { n: 30, u: 'm' };
    if (m % 86400000 === 0) return { n: m / 86400000, u: 'd' };
    if (m % 3600000 === 0) return { n: m / 3600000, u: 'h' };
    if (m % 60000 === 0) return { n: m / 60000, u: 'm' };
    if (m % 1000 === 0) return { n: m / 1000, u: 's' };
    return { n: Math.max(1, Math.round(m / 1000)), u: 's' };
  }

  function cronFillFormFromJobObject(job) {
    if (!job) return;
    var nameEl = document.getElementById('cron-in-name');
    if (nameEl) nameEl.value = job.id || '';
    var msgEl = document.getElementById('cron-in-message');
    if (msgEl) msgEl.value = job.prompt || '';
    var enEl = document.getElementById('cron-in-enabled');
    if (enEl) enEl.checked = !!job.enabled;
    var sess = String(job.sessionTarget || 'main').toLowerCase();
    var sessEl = document.getElementById('cron-in-session');
    var agentEl = document.getElementById('cron-in-agent');
    if (agentEl) agentEl.value = '';
    var opts = ['main', 'isolated', 'current'];
    if (sessEl) {
      if (opts.indexOf(sess) >= 0) {
        sessEl.value = sess;
      } else {
        sessEl.value = 'main';
        if (agentEl) agentEl.value = job.sessionTarget || '';
      }
    }
    var sch = job.schedule || {};
    var kind = String(sch.kind || 'every').toLowerCase();
    var stEl = document.getElementById('cron-in-schedule-type');
    if (stEl) {
      if (kind === 'at') stEl.value = 'at';
      else if (kind === 'cron') stEl.value = 'cron';
      else stEl.value = 'every';
    }
    if (kind === 'at') {
      var atMs = Number(sch.atMs || 0);
      var atIn = document.getElementById('cron-in-at');
      if (atIn) atIn.value = cronMsToDatetimeLocal(atMs);
    } else if (kind === 'cron') {
      var exIn = document.getElementById('cron-in-expr');
      var tzIn = document.getElementById('cron-in-tz');
      if (exIn) exIn.value = sch.cronExpr || '';
      if (tzIn) tzIn.value = sch.timeZone || 'UTC';
    } else {
      var evMs = Number(sch.everyMs || 60000);
      var fo = cronEveryMsToForm(evMs);
      var iv = document.getElementById('cron-in-interval');
      var iu = document.getElementById('cron-in-interval-unit');
      if (iv) iv.value = fo.n;
      if (iu) iu.value = fo.u;
    }
    var dch = document.getElementById('cron-in-delivery-channel');
    var dto = document.getElementById('cron-in-delivery-to');
    var dan = document.getElementById('cron-in-delivery-announce');
    if (dch) dch.value = job.deliveryChannel || '';
    if (dto) dto.value = job.deliveryTo || '';
    if (dan) dan.checked = !!job.deliveryAnnounce;
    var sev = document.getElementById('cron-in-system-event');
    var wkm = document.getElementById('cron-in-wake-mode');
    if (sev) sev.value = job.systemEvent || '';
    if (wkm) wkm.value = job.wakeMode || '';
    var t = document.getElementById('cron-in-schedule-type');
    var everyRow = document.getElementById('cron-row-every');
    var atRow = document.getElementById('cron-row-at');
    var cronRow = document.getElementById('cron-row-cron');
    if (t && everyRow && atRow && cronRow) {
      var tv = t.value || 'every';
      if (tv === 'at') {
        everyRow.style.display = 'none';
        atRow.style.display = '';
        cronRow.style.display = 'none';
      } else if (tv === 'cron') {
        everyRow.style.display = 'none';
        atRow.style.display = 'none';
        cronRow.style.display = '';
      } else {
        everyRow.style.display = '';
        atRow.style.display = 'none';
        cronRow.style.display = 'none';
      }
    }
  }

  function cronApplyFormModeUi() {
    var title = document.getElementById('cron-aside-title');
    var footerCancel = document.getElementById('cron-form-footer-cancel');
    var nameIn = document.getElementById('cron-in-name');
    if (title) {
      if (v3CronFormMode === 'edit') title.textContent = '编辑任务';
      else if (v3CronFormMode === 'clone') title.textContent = '克隆任务';
      else title.textContent = '新建任务';
    }
    if (footerCancel) {
      footerCancel.style.display = (v3CronFormMode === 'edit' || v3CronFormMode === 'clone') ? 'inline-flex' : 'none';
    }
    if (nameIn) {
      nameIn.readOnly = (v3CronFormMode === 'edit');
      nameIn.style.opacity = (v3CronFormMode === 'edit') ? '0.92' : '';
    }
    cronSyncNewTaskFormUi();
  }

  function cronResetFormToCreate() {
    v3CronFormMode = 'create';
    v3CronEditId = '';
    v3CronCloneJob = null;
    cronFillFormFromJobObject({ id: '', prompt: '', enabled: true, sessionTarget: 'main', schedule: { kind: 'every', everyMs: 1800000 } });
    var nameEl = document.getElementById('cron-in-name');
    if (nameEl) {
      nameEl.value = '';
      nameEl.readOnly = false;
      nameEl.style.opacity = '';
    }
    var agentEl = document.getElementById('cron-in-agent');
    if (agentEl) agentEl.value = '';
    var exR = document.getElementById('cron-in-expr');
    if (exR) exR.value = '';
    var tzR = document.getElementById('cron-in-tz');
    if (tzR) tzR.value = 'UTC';
    var dchR = document.getElementById('cron-in-delivery-channel');
    if (dchR) dchR.value = '';
    var dtoR = document.getElementById('cron-in-delivery-to');
    if (dtoR) dtoR.value = '';
    var danR = document.getElementById('cron-in-delivery-announce');
    if (danR) danR.checked = false;
    var seR = document.getElementById('cron-in-system-event');
    if (seR) seR.value = '';
    var wmR = document.getElementById('cron-in-wake-mode');
    if (wmR) wmR.value = '';
    cronApplyFormModeUi();
  }

  function cronRestoreEditFormAfterRender() {
    if (v3CronFormMode !== 'edit' || !v3CronEditId || !lastStatusData || !lastStatusData.cron) return;
    var jobs = lastStatusData.cron.jobs || [];
    var job = null;
    for (var i = 0; i < jobs.length; i++) {
      if (jobs[i].id === v3CronEditId) { job = jobs[i]; break; }
    }
    if (!job) return;
    cronFillFormFromJobObject(job);
    cronApplyFormModeUi();
  }

  function cronRestoreCloneFormAfterRender() {
    if (v3CronFormMode !== 'clone' || !v3CronCloneJob) return;
    cronFillFormFromJobObject(v3CronCloneJob);
    cronApplyFormModeUi();
  }

  function cronMarkSelectedJob(jobId) {
    v3CronSelectedId = jobId || '';
    try {
      var cards = document.querySelectorAll('.cron-task-card');
      for (var i = 0; i < cards.length; i++) {
        var c = cards[i];
        if (!c || !c.getAttribute) continue;
        var id = c.getAttribute('data-cron-id');
        if (id && id === v3CronSelectedId) {
          c.classList.add('cron-task-card--selected');
        } else {
          c.classList.remove('cron-task-card--selected');
        }
      }
    } catch (_e) {}
  }

  function cronJobFromDataset(btn) {
    var jid = btn.getAttribute('data-cron-id') || '';
    var sk = String(btn.getAttribute('data-cron-schedule-kind') || '').toLowerCase();
    var everyMs = Number(btn.getAttribute('data-cron-every-ms') || '0');
    var atMs = Number(btn.getAttribute('data-cron-at-ms') || '0');
    var cronEx = btn.getAttribute('data-cron-expr') || '';
    var cronTz = btn.getAttribute('data-cron-tz') || 'UTC';
    var sess = btn.getAttribute('data-cron-session') || 'main';
    var en = String(btn.getAttribute('data-cron-enabled') || 'true') === 'true';
    var msg = btn.getAttribute('data-cron-message') || '';
    var dch = btn.getAttribute('data-delivery-ch') || '';
    var dto = btn.getAttribute('data-delivery-to') || '';
    var dAnn = String(btn.getAttribute('data-delivery-ann') || 'false') === 'true';
    var sysEv = btn.getAttribute('data-system-event') || '';
    var wake = btn.getAttribute('data-wake-mode') || '';
    var sch;
    if (sk === 'at') sch = { kind: 'at', atMs: atMs, everyMs: 0, cronExpr: '', timeZone: 'UTC' };
    else if (sk === 'cron') sch = { kind: 'cron', cronExpr: cronEx, timeZone: cronTz, everyMs: 0, atMs: 0 };
    else sch = { kind: 'every', everyMs: everyMs, atMs: 0, cronExpr: '', timeZone: 'UTC' };
    return { id: jid, prompt: msg, enabled: en, sessionTarget: sess, schedule: sch, deliveryChannel: dch, deliveryTo: dto, deliveryAnnounce: dAnn, systemEvent: sysEv, wakeMode: wake };
  }

  function cronSyncNewTaskFormUi() {
    var errEl = document.getElementById('cron-form-errors');
    var btn = document.getElementById('cron-submit-btn');
    var hint = document.getElementById('cron-form-errors-hint');
    if (!btn || !errEl) return;
    btn.textContent = (v3CronFormMode === 'edit') ? '保存更改' : '添加任务';
    var errors = [];
    var name = (document.getElementById('cron-in-name') || {}).value || '';
    if (!String(name).trim()) {
      errors.push({ id: 'cron-in-name', title: '名称', msg: '名称为必填项。' });
    }
    var msg = (document.getElementById('cron-in-message') || {}).value || '';
    if (!String(msg).trim()) {
      errors.push({ id: 'cron-in-message', title: '助手任务提示', msg: '代理消息为必填项。' });
    }
    var st = (document.getElementById('cron-in-schedule-type') || {}).value || 'every';
    if (st === 'at') {
      var atVal = (document.getElementById('cron-in-at') || {}).value || '';
      if (!atVal) {
        errors.push({ id: 'cron-in-at', title: '时间', msg: '请选择一次性任务的执行时间。' });
      }
    } else if (st === 'cron') {
      var exVal = String((document.getElementById('cron-in-expr') || {}).value || '').trim();
      if (!exVal) {
        errors.push({ id: 'cron-in-expr', title: '表达式', msg: '请填写五段式 cron。' });
      }
    } else {
      var n = parseFloat((document.getElementById('cron-in-interval') || {}).value || '0');
      if (!Number.isFinite(n) || n <= 0) {
        errors.push({ id: 'cron-in-interval', title: '每隔', msg: '请填写有效的间隔。' });
      }
    }
    var cnt = errors.length;
    btn.disabled = cnt > 0;
    if (hint) {
      hint.textContent = cnt ? ('修复 ' + cnt + ' 个字段以继续。') : '';
    }
    if (cnt === 0) {
      errEl.style.display = 'none';
      errEl.innerHTML = '';
      return;
    }
    errEl.style.display = '';
    var links = errors.map(function(er) {
      return '<a href="#" class="cron-form-error-link" data-cron-focus="' + String(er.id).replace(new RegExp('"', 'g'), '&quot;') + '">' +
        String(er.title).replace(new RegExp('<', 'g'), '&lt;').replace(new RegExp('>', 'g'), '&gt;') + ': ' +
        String(er.msg).replace(new RegExp('<', 'g'), '&lt;').replace(new RegExp('>', 'g'), '&gt;') + '</a>';
    }).join('');
    var errTitle = (v3CronFormMode === 'edit') ? '暂无法保存任务' : '暂无法添加任务';
    errEl.innerHTML =
      '<div class="cron-form-errors__inner">' +
        '<div class="cron-form-errors__title">' + errTitle + '</div>' +
        '<div class="cron-form-errors__intro">填写下方必填项以启用提交。</div>' +
        '<div class="cron-form-errors__list">' + links + '</div>' +
      '</div>';
  }

  function wireCronPanel() {
    if (window.__cjCronPanelWired) {
      setTimeout(function() {
        var t = document.getElementById('cron-in-schedule-type');
        var everyRow = document.getElementById('cron-row-every');
        var atRow = document.getElementById('cron-row-at');
        var cronRow = document.getElementById('cron-row-cron');
        if (t && everyRow && atRow && cronRow) {
          var tv = t.value || 'every';
          if (tv === 'at') {
            everyRow.style.display = 'none';
            atRow.style.display = '';
            cronRow.style.display = 'none';
          } else if (tv === 'cron') {
            everyRow.style.display = 'none';
            atRow.style.display = 'none';
            cronRow.style.display = '';
          } else {
            everyRow.style.display = '';
            atRow.style.display = 'none';
            cronRow.style.display = 'none';
          }
        }
        cronSyncNewTaskFormUi();
        cronRestoreEditFormAfterRender();
        cronRestoreCloneFormAfterRender();
      }, 0);
      return;
    }
    window.__cjCronPanelWired = true;

    function reRender() {
      if (lastStatusData) { renderShell(lastStatusData); }
    }

    document.addEventListener('change', function(e) {
      const t = e.target;
      if (!t || !t.id) return;
      if (t.id === 'cron-in-schedule-type') {
        var everyRow = document.getElementById('cron-row-every');
        var atRow = document.getElementById('cron-row-at');
        var cronRow = document.getElementById('cron-row-cron');
        if (everyRow && atRow && cronRow) {
          var tv = t.value || 'every';
          if (tv === 'at') {
            everyRow.style.display = 'none';
            atRow.style.display = '';
            cronRow.style.display = 'none';
          } else if (tv === 'cron') {
            everyRow.style.display = 'none';
            atRow.style.display = 'none';
            cronRow.style.display = '';
          } else {
            everyRow.style.display = '';
            atRow.style.display = 'none';
            cronRow.style.display = 'none';
          }
        }
        cronSyncNewTaskFormUi();
        return;
      }
      if (t.id === 'cron-filter-enabled') {
        v3CronEnableFilter = t.value || 'all';
        reRender();
        return;
      }
      if (t.id === 'cron-filter-schedule') {
        v3CronScheduleFilter = t.value || 'all';
        reRender();
        return;
      }
      if (t.id === 'cron-filter-lastrun') {
        v3CronLastRunFilter = t.value || 'all';
        reRender();
        return;
      }
      if (t.id === 'cron-sort') {
        v3CronSort = t.value || 'next';
        reRender();
        return;
      }
      if (t.id === 'cron-sort-dir') {
        v3CronSortDir = t.value || 'asc';
        reRender();
        return;
      }
      if (t.id === 'cron-run-scope') {
        v3CronRunScope = t.value || 'all';
        reRender();
        return;
      }
      if (t.id === 'cron-run-sort') {
        v3CronRunSort = t.value || 'newest';
        reRender();
        return;
      }
      if (t.id === 'cron-run-status') {
        v3CronRunStatusFilter = t.value || 'all';
        reRender();
        return;
      }
      if (t.id === 'cron-run-delivery') {
        v3CronRunDeliveryFilter = t.value || 'all';
        reRender();
        return;
      }
    });

    var __cronSearchDebounce = null;
    var __cronRunSearchDebounce = null;
    document.addEventListener('input', function(e) {
      const t = e.target;
      if (t && t.id && t.id.indexOf('cron-in-') === 0) {
        cronSyncNewTaskFormUi();
      }
      if (t && t.id === 'cron-run-search') {
        const v2 = t.value || '';
        if (__cronRunSearchDebounce) {
          try { clearTimeout(__cronRunSearchDebounce); } catch (_e2) {}
        }
        __cronRunSearchDebounce = setTimeout(function() {
          v3CronRunSearch = v2;
          reRender();
        }, 200);
        return;
      }
      if (!t || t.id !== 'cron-filter-search') return;
      const v = t.value || '';
      if (__cronSearchDebounce) {
        try { clearTimeout(__cronSearchDebounce); } catch (_e) {}
      }
      __cronSearchDebounce = setTimeout(function() {
        v3CronFilterText = v;
        reRender();
      }, 200);
    });

    document.addEventListener('click', function(e) {
      const errLink = (e.target && e.target.closest) ? e.target.closest('.cron-form-error-link') : null;
      if (errLink) {
        e.preventDefault();
        var fid = errLink.getAttribute('data-cron-focus') || '';
        if (fid) {
          var fel = document.getElementById(fid);
          if (fel) {
            fel.focus();
            try { fel.select(); } catch (_e2) {}
          }
        }
        return;
      }
      var cancelEl = e.target;
      if (cancelEl && cancelEl.nodeType === 3) cancelEl = cancelEl.parentElement;
      var footerCancelBtn = (cancelEl && cancelEl.closest) ? cancelEl.closest('#cron-form-footer-cancel') : null;
      if (footerCancelBtn) {
        e.preventDefault();
        cronResetFormToCreate();
        return;
      }
      const btn = (e.target && e.target.closest) ? e.target.closest('#cron-refresh-btn, #cron-filter-reset, [data-cron-action], .cron-task-card') : null;
      if (!btn) return;
      if (btn.id === 'cron-refresh-btn') {
        e.preventDefault();
        loadStatus().catch(function(err) { console.warn(err); });
        return;
      }
      if (btn.id === 'cron-filter-reset') {
        e.preventDefault();
        v3CronFilterText = '';
        v3CronEnableFilter = 'all';
        v3CronScheduleFilter = 'all';
        v3CronLastRunFilter = 'all';
        v3CronSort = 'next';
        v3CronSortDir = 'asc';
        v3CronRunScope = 'all';
        v3CronRunSearch = '';
        v3CronRunSort = 'newest';
        v3CronRunStatusFilter = 'all';
        v3CronRunDeliveryFilter = 'all';
        reRender();
        return;
      }
      const act = btn.getAttribute('data-cron-action') || '';
      const jid = btn.getAttribute('data-cron-id') || btn.getAttribute('data-cron-id');
      if (act === 'focus_run_history') {
        e.preventDefault();
        if (!jid) { return; }
        v3CronRunScope = jid;
        cronMarkSelectedJob(jid);
        reRender();
        setTimeout(function() {
          var sec = document.querySelector('.cron-section--run-history');
          if (sec) { sec.scrollIntoView({ behavior: 'smooth', block: 'nearest' }); }
        }, 60);
        return;
      }
      if (!act) {
        const cid = btn.getAttribute('data-cron-id');
        if (cid) {
          e.preventDefault();
          cronMarkSelectedJob(cid);
        }
        return;
      }
      if (!jid) return;
      e.preventDefault();
      var payload;
      if (act === 'edit') {
        v3CronFormMode = 'edit';
        v3CronEditId = jid;
        v3CronCloneJob = null;
        cronFillFormFromJobObject(cronJobFromDataset(btn));
        cronMarkSelectedJob(jid);
        cronApplyFormModeUi();
        var aside = document.querySelector('.cron-aside');
        if (aside) aside.scrollIntoView({ behavior: 'smooth', block: 'nearest' });
        return;
      } else if (act === 'clone') {
        v3CronFormMode = 'clone';
        v3CronEditId = '';
        var cloneJob = cronJobFromDataset(btn);
        cloneJob.id = jid + '-copy';
        v3CronCloneJob = cloneJob;
        cronFillFormFromJobObject(cloneJob);
        cronMarkSelectedJob(jid);
        cronApplyFormModeUi();
        var aside2 = document.querySelector('.cron-aside');
        if (aside2) aside2.scrollIntoView({ behavior: 'smooth', block: 'nearest' });
        return;
      } else if (act === 'remove') {
        payload = { action: 'remove', id: jid };
      } else if (act === 'enable') {
        payload = { action: 'enable', id: jid };
      } else if (act === 'disable') {
        payload = { action: 'disable', id: jid };
      } else if (act === 'run_once') {
        payload = { action: 'run_once', id: jid };
      } else {
        return;
      }
      if (act === 'enable') {
        btn.textContent = '禁用';
        btn.setAttribute('data-cron-action', 'disable');
        const row = btn.closest ? btn.closest('tr') : null;
        const nameCell = row ? row.querySelector('td') : null;
        if (nameCell && nameCell.innerHTML.indexOf('已启用') < 0) {
          nameCell.innerHTML = nameCell.innerHTML + '<div class="muted" style="font-size:11px;margin-top:4px;"><span class="cron-badge--yes">已启用</span></div>';
        }
      } else if (act === 'disable') {
        btn.textContent = '启动';
        btn.setAttribute('data-cron-action', 'enable');
        const row = btn.closest ? btn.closest('tr') : null;
        const nameCell = row ? row.querySelector('td') : null;
        if (nameCell) {
          nameCell.innerHTML = String(nameCell.innerHTML || '').replace(new RegExp('<div class="muted" style="font-size:11px;margin-top:4px;"><span class="cron-badge--yes">已启用</span></div>', 'g'), '<div class="muted" style="font-size:11px;margin-top:4px;">已禁用</div>');
        }
      }
      apiPost('/api/cron', payload).then(function(r) {
        if (r && r.ok) {
          loadStatus().catch(function(err) { console.warn(err); });
        } else {
          alert((r && r.message) ? r.message : '操作失败');
        }
      }).catch(function(err) {
        console.warn(err);
        alert(String(err && err.message ? err.message : err));
      });
    });

    document.addEventListener('submit', function(e) {
      const f = e.target;
      if (!f || f.id !== 'cron-form-new') return;
      e.preventDefault();
      cronSyncNewTaskFormUi();
      var subBtn = document.getElementById('cron-submit-btn');
      if (subBtn && subBtn.disabled) {
        return;
      }
      var name = (document.getElementById('cron-in-name') || {}).value || '';
      var agent = (document.getElementById('cron-in-agent') || {}).value || '';
      var sess = (document.getElementById('cron-in-session') || {}).value || 'main';
      var session = String(agent).trim() || sess;
      var message = (document.getElementById('cron-in-message') || {}).value || '';
      var en = !!(document.getElementById('cron-in-enabled') || {}).checked;
      var st = (document.getElementById('cron-in-schedule-type') || {}).value || 'every';
      var payload;
      if (v3CronFormMode === 'edit' && v3CronEditId) {
        var everyStrEdit = '';
        var atStrEdit = '';
        var cronExSave = '';
        var tzSave = 'UTC';
        if (st === 'at') {
          var atElEd = document.getElementById('cron-in-at');
          var atValEd = atElEd ? atElEd.value : '';
          if (!atValEd) {
            cronSyncNewTaskFormUi();
            return;
          }
          var atMsEd = new Date(atValEd).getTime();
          if (!Number.isFinite(atMsEd) || atMsEd <= 0) {
            cronSyncNewTaskFormUi();
            return;
          }
          atStrEdit = String(atMsEd);
        } else if (st === 'cron') {
          cronExSave = String((document.getElementById('cron-in-expr') || {}).value || '').trim();
          tzSave = String((document.getElementById('cron-in-tz') || {}).value || 'UTC').trim();
          if (!cronExSave) {
            cronSyncNewTaskFormUi();
            return;
          }
        } else {
          var nEd = parseFloat((document.getElementById('cron-in-interval') || {}).value || '0');
          var unitEd = (document.getElementById('cron-in-interval-unit') || {}).value || 'm';
          if (!nEd || nEd <= 0 || !Number.isFinite(nEd)) {
            cronSyncNewTaskFormUi();
            return;
          }
          if (unitEd === 's') { everyStrEdit = Math.round(nEd) + 's'; }
          else if (unitEd === 'm') { everyStrEdit = Math.round(nEd) + 'm'; }
          else if (unitEd === 'h') { everyStrEdit = Math.round(nEd) + 'h'; }
          else if (unitEd === 'd') { everyStrEdit = Math.round(nEd) + 'd'; }
          else { everyStrEdit = Math.round(nEd) + 'm'; }
        }
        payload = {
          action: 'save_job',
          id: v3CronEditId,
          message: message,
          session: session,
          enabled: en ? 'true' : 'false',
          schedule_kind: st,
          every: everyStrEdit,
          at: atStrEdit,
          cron_expr: cronExSave,
          time_zone: tzSave,
          delivery_channel: (document.getElementById('cron-in-delivery-channel') || {}).value || '',
          delivery_to: (document.getElementById('cron-in-delivery-to') || {}).value || '',
          delivery_announce: (document.getElementById('cron-in-delivery-announce') || {}).checked ? 'true' : 'false',
          system_event: (document.getElementById('cron-in-system-event') || {}).value || '',
          wake_mode: (document.getElementById('cron-in-wake-mode') || {}).value || ''
        };
        if (!String(payload.message || '').trim()) {
          cronSyncNewTaskFormUi();
          return;
        }
        apiPost('/api/cron', payload).then(function(r) {
          if (r && r.ok) {
            cronResetFormToCreate();
            loadStatus().catch(function(err) { console.warn(err); });
          } else {
            alert((r && r.message) ? r.message : '保存失败');
          }
        }).catch(function(err) {
          console.warn(err);
          alert(String(err && err.message ? err.message : err));
        });
        return;
      }
      var cronExtra = {
        delivery_channel: (document.getElementById('cron-in-delivery-channel') || {}).value || '',
        delivery_to: (document.getElementById('cron-in-delivery-to') || {}).value || '',
        delivery_announce: (document.getElementById('cron-in-delivery-announce') || {}).checked ? 'true' : 'false',
        system_event: (document.getElementById('cron-in-system-event') || {}).value || '',
        wake_mode: (document.getElementById('cron-in-wake-mode') || {}).value || ''
      };
      if (st === 'at') {
        var atEl = document.getElementById('cron-in-at');
        var atVal = atEl ? atEl.value : '';
        if (!atVal) {
          cronSyncNewTaskFormUi();
          return;
        }
        var atMs = new Date(atVal).getTime();
        if (!Number.isFinite(atMs) || atMs <= 0) {
          cronSyncNewTaskFormUi();
          return;
        }
        payload = Object.assign({
          action: 'add_at',
          name: name.trim(),
          at: String(atMs),
          session: session,
          message: message
        }, cronExtra);
      } else if (st === 'cron') {
        var exNew = String((document.getElementById('cron-in-expr') || {}).value || '').trim();
        var tzNew = String((document.getElementById('cron-in-tz') || {}).value || 'UTC').trim();
        if (!exNew) {
          cronSyncNewTaskFormUi();
          return;
        }
        payload = Object.assign({
          action: 'add_cron',
          name: name.trim(),
          cron_expr: exNew,
          time_zone: tzNew,
          session: session,
          message: message
        }, cronExtra);
      } else {
        var n = parseFloat((document.getElementById('cron-in-interval') || {}).value || '0');
        var unit = (document.getElementById('cron-in-interval-unit') || {}).value || 'm';
        if (!n || n <= 0 || !Number.isFinite(n)) {
          cronSyncNewTaskFormUi();
          return;
        }
        var everyStr = '';
        if (unit === 's') { everyStr = Math.round(n) + 's'; }
        else if (unit === 'm') { everyStr = Math.round(n) + 'm'; }
        else if (unit === 'h') { everyStr = Math.round(n) + 'h'; }
        else if (unit === 'd') { everyStr = Math.round(n) + 'd'; }
        else { everyStr = Math.round(n) + 'm'; }
        payload = Object.assign({
          action: 'add_every',
          name: name.trim(),
          every: everyStr,
          session: session,
          message: message
        }, cronExtra);
      }
      if (!payload.name || !String(payload.message || '').trim()) {
        cronSyncNewTaskFormUi();
        return;
      }
      apiPost('/api/cron', payload).then(function(r) {
        if (r && r.ok) {
          var jobId = payload.name;
          if (!en && jobId) {
            return apiPost('/api/cron', { action: 'disable', id: jobId }).then(function() {
              loadStatus().catch(function(err) { console.warn(err); });
            });
          }
          loadStatus().catch(function(err) { console.warn(err); });
        } else {
          alert((r && r.message) ? r.message : '添加失败');
        }
      }).catch(function(err) {
        console.warn(err);
        alert(String(err && err.message ? err.message : err));
      });
    });

    setTimeout(function() {
      cronSyncNewTaskFormUi();
      cronRestoreEditFormAfterRender();
      cronRestoreCloneFormAfterRender();
    }, 0);
  }

"""
}
