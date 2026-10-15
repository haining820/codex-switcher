import { readFileSync, writeFileSync, renameSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';
import { createInterface } from 'node:readline/promises';

function modelsURL() {
  const base = process.env.COMPANY_CODEX_GATEWAY;
  if (!base) throw new Error('请先配置 COMPANY_CODEX_GATEWAY。');
  let url;
  try { url = new URL(base); } catch { throw new Error('公司网关地址格式不正确。'); }
  if (!['http:', 'https:'].includes(url.protocol) || url.username || url.password || url.search || url.hash
      || url.hostname === 'gateway.example.com') {
    throw new Error('公司网关地址格式不正确，请勿在地址中包含凭据。');
  }
  return base.replace(/\/+$/, '') + '/models';
}

export function normalizeModels(payload) {
  if (!Array.isArray(payload?.data)) throw new Error('模型目录格式不正确。');
  const seen = new Set();
  const models = [];
  for (const item of payload.data) {
    const id = item?.id;
    if (typeof id !== 'string' || !/^[\x21-\x7e]{1,200}$/.test(id) || seen.has(id)) continue;
    seen.add(id);
    models.push({
      id,
      tags: Array.isArray(item.tag_list)
        ? item.tag_list.filter(tag => typeof tag === 'string').map(tag => tag.replace(/[\x00-\x1f\x7f-\x9f]/g, '').slice(0, 40)).slice(0, 5)
        : [],
    });
  }
  if (!models.length) throw new Error('公司网关没有返回可选模型。');
  return models;
}

export function orderModels(models, previous) {
  const preferred = models.find(model => model.id === previous)
    ?? models.find(model => /^gpt-/i.test(model.id))
    ?? models[0];
  return [preferred, ...models.filter(model => model.id !== preferred.id)];
}

export function selectionIndex(answer, count) {
  const trimmed = answer.trim();
  if (trimmed === '') return 0;
  if (!/^[1-9]\d*$/.test(trimmed)) return -1;
  const number = Number(trimmed);
  return Number.isSafeInteger(number) && number <= count ? number - 1 : -1;
}

async function fetchModels(token) {
  let response;
  try {
    response = await fetch(modelsURL(), {
      headers: { Authorization: `Bearer ${token}`, Accept: 'application/json' },
      signal: AbortSignal.timeout(15000),
      redirect: 'error',
    });
  } catch {
    throw new Error('无法连接公司模型目录，请检查公司网络或 VPN。');
  }
  if (!response.ok) {
    throw new Error(response.status === 401 || response.status === 403
      ? `公司模型目录认证失败（HTTP ${response.status}），请检查 Token 和权限。`
      : `公司模型目录请求失败（HTTP ${response.status}）。`);
  }
  let payload;
  try {
    payload = await response.json();
  } catch {
    throw new Error('公司模型目录未返回有效 JSON。');
  }
  return normalizeModels(payload);
}

async function main() {
  const stateDir = process.argv[2];
  if (!stateDir || !process.env.ADA_API_KEY) throw new Error('缺少公司独立目录或 Token。');
  const previousFile = join(stateDir, 'last-selected-model.txt');
  let previous = '';
  try { previous = readFileSync(previousFile, 'utf8').trim(); } catch {}
  const listOnly = process.argv.includes('--list');
  const terminal = listOnly ? null : createInterface({ input: process.stdin, output: process.stderr });
  try {
    while (true) {
      console.error('\n正在实时查询公司模型列表……');
      let models;
      try {
        models = orderModels(await fetchModels(process.env.ADA_API_KEY), previous);
      } catch (error) {
        console.error(error.message);
        if (listOnly) throw new Error('实时模型查询失败。');
        const retry = await terminal.question('回车重新查询，输入 q 退出：');
        if (retry.trim().toLowerCase() === 'q') return;
        continue;
      }
      console.error(`已实时获取 ${models.length} 个模型；时间：${new Date().toLocaleString('zh-CN', { timeZone: 'Asia/Shanghai', hour12: false })}`);
      console.error('来源：公司 Codex 网关 /models；具体调用权限以网关实际响应为准。');
      for (const [index, model] of models.entries()) {
        console.error(`${String(index + 1).padStart(2)}. ${model.id}${index === 0 ? '  [回车默认]' : ''}${model.tags.length ? '  | ' + model.tags.join(' / ') : ''}`);
      }
      if (listOnly) return;
      console.error('\n输入编号选择；回车使用默认项；r 刷新；q 退出。');
      let refresh = false;
      while (true) {
        const answer = await terminal.question('选择模型：');
        const choice = answer.trim().toLowerCase();
        if (choice === 'q') return;
        if (choice === 'r') { refresh = true; break; }
        const index = selectionIndex(answer, models.length);
        if (index < 0) { console.error(`请输入 1 到 ${models.length} 的编号。`); continue; }
        const model = models[index];
        const temporaryFile = previousFile + `.${process.pid}.tmp`;
        writeFileSync(temporaryFile, model.id + '\n', { mode: 0o600 });
        renameSync(temporaryFile, previousFile);
        console.error(`已选择：${model.id}`);
        process.stdout.write(model.id + '\n');
        return;
      }
      if (refresh) continue;
    }
  } finally {
    terminal?.close();
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  main().catch(error => {
    console.error(error.code === 'ERR_USE_AFTER_CLOSE' ? '输入已结束，已取消启动。' : error.message);
    process.exitCode = 1;
  });
}
