/* TechRental · front end ligado ao banco MySQL. Os dados vêm de api.php (e o login de login.php); nada fica só no navegador. */
let SET = { dev: ['Desenvolvimento de Software', 'Software'], pd: ['Engenharia e Prototipagem (P&D)', 'P&D'], cp: ['Implantação e Operações em Campo', 'Campo'], ms: ['Manutenção e Suporte Técnico', 'Suporte'] };
const MAIL = { dev: 'gestor.software', pd: 'gestor.pd', cp: 'gestor.campo', ms: 'gestor.suporte' };
const PERF = { a: 'Almoxarifado e Patrimônio', d: 'Diretoria' };
let CAT = ['Notebooks', 'Kits Eletrônicos', 'Ferramentas', 'Equipamentos Tecnológicos'], CATS = [];
const ST = { d: ['verde', 'Disponível'], e: ['amarelo', 'Emprestado'], a: ['vermelho', 'Atrasado'], m: ['amarelo', 'Em manutenção'], i: ['cinza', 'Descartado'] };
// Dados carregados do banco por carregar() (formatos explicados em api.php):
// IT: equipamentos {id, c código, n nome, k índice da categoria, s sigla do setor, st d|e|a|m|i, uso, ...}
// EMP: código -> [OS, prazo dd/mm, extensão n|p|u, situação, id do empréstimo, retirada, prazo completo]
// SOL: solicitações pendentes · EXT: extensões · COMPRA: alertas de compra · MAN: manutenções abertas
// HIS: histórico devolvido (tela Histórico) · HD: histórico completo (detalhe do equipamento) · USR: usuários
let IT = [], EMP = {}, SOL = [], EXT = [], COMPRA = [], MAN = [], HIS = [], HD = [], USR = [], CK = [], CKID = [];
const DS = { open: ['vermelho', 'Em aberto'], ok: ['verde', 'Íntegro'], rep: ['verde', 'Reposição simples'], man: ['amarelo', 'Manutenção'], des: ['cinza', 'Descartado'] };
// histórico de movimentações de um equipamento (vem do banco)
const hist = x => HD.filter(h => h[0] == x.c).map(h => h.slice(1));
const MENU = {
  a: [['Painel', 'painel'], ['Catálogo', 'catalogo'], ['Solicitações', 'solicitacoes'], ['Empréstimos', 'emprestimos'], ['Histórico', 'historico'], ['Manutenção', 'manutencao'], ['Cadastros', 'cadastros']],
  g: [['Painel', 'painel'], ['Catálogo', 'catalogo'], ['Nova retirada', 'nova-retirada'], ['Meus empréstimos', 'emprestimos'], ['Extensões', 'extensoes'], ['Histórico', 'historico']],
  d: [['Painel', 'painel'], ['Aprovações', 'aprovacoes'], ['Catálogo', 'catalogo'], ['Histórico', 'historico'], ['Setores', 'setores']]
};
const LOGO = '<svg viewBox="0 0 34 34" aria-hidden="true"><rect width="34" height="34" rx="6" fill="#ac1a3f"/><path d="M9 7h11l5 5v15H9z" fill="#fff"/><path d="M13 17h8m0 0-2.5-2.5M21 17l-2.5 2.5M21 22h-8m0 0 2.5-2.5M13 22l2.5 2.5" stroke="#ac1a3f" stroke-width="1.6" fill="none" stroke-linecap="round" stroke-linejoin="round"/></svg>';

/* ---------- utilidades ---------- */
const P = document.body.dataset.p, Q = new URLSearchParams(location.search), $ = s => document.querySelector(s);
let U = JSON.parse(sessionStorage.getItem('tr') || 'null'); // {p: 'a'|'g'|'d', s: setor do gestor}; o servidor confirma em carregar()
const H = { 'X-TR': '1' };
const X = { v: {}, f: 'todos', t: 'x', m: '' }; // estado da tela
const F = p => ({ detalhe: 'detalhe-equipamento', devolucao: 'registrar-devolucao' }[p] || p) + '.html';
const ACT = { detalhe: 'catalogo', devolucao: 'emprestimos' };
const item = c => IT.find(x => x.c === c);
const sel = (c, t) => `<span class="selo selo-${c}">${t}</span>`;
const cod = c => `<span class="codigo">${c}</span>`;
const cor = s => s.startsWith('Atras') ? 'vermelho' : s.startsWith('Devolve') ? 'amarelo' : 'verde';
const cab = (r, t) => `<div class="cabecalho-pagina"><p class="rotulo-mono">${r}</p><h1>${t}</h1></div>`;
const ind = (l, n, t, al) => `<div class="indicador${al ? ' alerta' : ''}"><p class="rotulo-mono">${l}</p><div class="numero">${n}</div><p>${t}</p></div>`;
const tab = (th, rows) => `<div class="cartao"><table class="tabela"><thead><tr>${th.map(x => `<th>${x}</th>`).join('')}</tr></thead><tbody>${rows.map(r => `<tr>${r.map(x => `<td>${x}</td>`).join('')}</tr>`).join('') || `<tr><td colspan="${th.length}">Nada por aqui.</td></tr>`}</tbody></table></div>`;
const btn = (t, a, i, c = 'btn-neutro') => `<button type="button" class="${c}" data-a="${a}" data-i="${i}">${t}</button>`;
const pills = (lista, atual, a) => `<div class="filtros">${lista.map(([k, t]) => `<button type="button" class="filtro${k == atual ? ' ativo' : ''}" data-a="${a}" data-i="${k}">${t}</button>`).join('')}</div>`;
const v = n => X.v[n] ?? '';
const atencao = l => `<aside class="cartao"><div class="cartao-titulo rotulo-mono">Atenção agora</div><div class="lista-atencao">${l.map(([h, t]) => `<div class="item-atencao"><h3>${h}</h3><p>${t}</p></div>`).join('')}</div></aside>`;
const vis = () => U.p == 'g' ? IT.filter(x => x.s == U.s) : IT;
const nSet = k => IT.filter(x => x.s == k);
const uso = () => tab(['Setor', 'Emprestados', 'Atrasados', 'Em manutenção'], Object.keys(SET).map(k => [SET[k][1], nSet(k).filter(x => EMP[x.c]).length, nSet(k).filter(x => x.st == 'a').length, nSet(k).filter(x => x.st == 'm').length]));

/* ---------- barra de navegação (muda por perfil) ---------- */
function nav() {
  const m = MENU[U.p].slice();
  if (U.p == 'g' && U.s == 'ms') m.splice(4, 0, ['Oficina', 'manutencao']); // só o Gestor de Suporte
  const nome = U.p == 'g' ? SET[U.s][0] : PERF[U.p];
  return `<header class="navbar"><a href="painel.html" class="logo" style="text-decoration:none">${LOGO}<span>Tech<strong>Rental</strong></span></a>
  <ul class="menu">${m.map(x => `<li><a href="${F(x[1])}" class="${(ACT[P] || P) == x[1] ? 'ativo' : ''}">${x[0]}</a></li>`).join('')}</ul>
  <div class="navbar-direita">
  <div class="usuario"><div class="usuario-info"><span class="usuario-perfil">SETOR LOGADO</span><span class="usuario-nome">${nome}</span></div><a href="login.html" class="btn-neutro" id="sair">Sair</a></div></div></header>`;
}

/* ---------- telas ---------- */
const R = {};

R.login = () => {
  const p = X.v.perfil || 'g', st = X.v.setor || 'dev', em = (p == 'g' ? MAIL[st] : { a: 'almoxarifado', d: 'diretoria' }[p]) + '@techrental.com';
  return `<div class="logo"><img class="logo-login" src="img/logo-techrental.png" alt="TechRental"></div>
  <main class="cartao-login ${Q.get('erro') ? 'com-erro' : ''}" id="cartao-login"><p class="rotulo-mono">Acesso restrito · uso interno</p><h1>Entrar no sistema</h1>
  <p class="mensagem-erro" role="alert">E-mail ou senha incorretos. Confira os dados e tente novamente.</p>
  <form id="f-login"><div class="campo"><label>Perfil de acesso</label>${pills([['a', 'Almoxarifado'], ['g', 'Gestor'], ['d', 'Diretoria']], p, 'perfil')}</div>
  ${p == 'g' ? `<div class="campo"><label for="setor">Setor</label><div class="campo-input"><select id="setor" name="setor" class="input-texto">${Object.keys(SET).map(k => `<option value="${k}"${k == st ? ' selected' : ''}>${SET[k][0]}</option>`).join('')}</select></div></div>` : ''}
  <div class="campo"><label for="email">E-mail</label><div class="campo-input"><input type="email" id="email" value="${em}" required></div></div>
  <div class="campo"><label for="senha">Senha</label><div class="campo-input"><input type="password" id="senha" value="12345678" required></div></div>
  <button type="submit" class="btn-entrar">Entrar</button></form>
  <p class="aviso-acesso">Acesso exclusivo para usuários cadastrados. Para obter ou recuperar o acesso, fale com o Almoxarifado.</p></main>
  <p class="rotulo-mono rodape-login">TechRental · sistema interno de empréstimos</p>`;
};

R.painel = () => {
  const V = vis(), ab = V.filter(x => EMP[x.c]), at = V.filter(x => x.st == 'a'), sol = SOL.filter(x => x.st == 'p'), ex = EXT.filter(x => x.st == 'p'), cp = COMPRA.filter(x => x.st == 'p');
  if (U.p == 'g') {
    return cab('Setor · ' + SET[U.s][1], 'Painel do setor') + `<section class="indicadores">${ind('Itens do setor', V.length, 'vinculados ao setor')}${ind('Emprestados', ab.length, 'com OS ativa')}${ind('Em atraso', at.length, 'sem bloqueio de novos pedidos', 1)}${ind('Extensões pendentes', ex.filter(x => item(x.it).s == U.s).length, 'aguardando a Diretoria')}</section>
    <div class="painel-grade">${tab(['Item', 'OS', 'Prazo', ''], ab.map(x => [cod(x.c) + '<br>' + x.n, EMP[x.c][0], sel(cor(EMP[x.c][3]), EMP[x.c][3]), EMP[x.c][2] == 'n' ? '<a class="btn-neutro" href="extensoes.html">Pedir extensão</a>' : sel('cinza', EMP[x.c][2] == 'p' ? 'Extensão pendente' : 'Extensão usada')]))}
    ${atencao([['Devolução em mãos', 'Leve o item ao Almoxarifado, que faz a vistoria e registra a devolução.'], ['Atraso não bloqueia o setor', 'Você pode seguir fazendo novas retiradas.']])}</div>`;
  }
  if (U.p == 'a') {
    return cab('Almoxarifado', 'Painel de controle') + `<section class="indicadores">${ind('Ativos registrados', IT.length, CAT.length + ' categorias · ' + Object.keys(SET).length + ' setores')}${ind('Emprestados', ab.length, at.length + ' atrasados')}${ind('Solicitações', sol.length, 'aguardando aprovação', 1)}${ind('Manutenção', MAN.length, MAN.filter(x => x.et == 'c').length + ' a validar')}</section>
    <div class="painel-grade">${tab(['Setor', 'Item', 'OS', ''], sol.map(x => [SET[item(x.it).s][1], item(x.it).n, x.os, '<a class="btn-secundario" href="solicitacoes.html">Analisar</a>']))}
    ${atencao([['Reparo concluído', MAN.filter(x => x.et == 'c').map(x => item(x.c).n).join(', ') || 'Nenhum item aguardando validação.'], ['Devoluções atrasadas', at.length + ' empréstimo(s) com prazo vencido.'], ['Alerta de compra', cp.length + ' item(ns) descartado(s) aguardando a Diretoria.']])}</div>`;
  }
  return cab('Diretoria', 'Visão estratégica') + `<section class="indicadores">${ind('Ativos', IT.length, IT.filter(x => x.st == 'i').length + ' descartado')}${ind('Emprestados', ab.length, 'em 4 setores')}${ind('Atrasados', at.length, 'sem bloqueio de setor', 1)}${ind('Pendências', ex.length + cp.length, ex.length + ' extensões · ' + cp.length + ' compra', 1)}</section>
  <div class="painel-grade"><div><p class="rotulo-mono" style="margin-bottom:8px">Uso por setor</p>${uso()}</div>${atencao([['Extensões de prazo', ex.length + ' pedido(s) aguardando decisão.'], ['Alertas de compra', cp.length + ' item(ns) descartado(s).'], ['Ir para', '<a href="aprovacoes.html">Aprovações</a>']])}</div>`;
};

R.catalogo = () => {
  const q = (Q.get('q') || '').toLowerCase(), L = vis().filter(x => (X.f == 'todos' || x.k == X.f) && (!X.s || x.s == X.s) && (!q || (x.c + x.n + (EMP[x.c] ? EMP[x.c][0] : '')).toLowerCase().includes(q)));
  const card = x => {
    let b = `<a class="btn-neutro" href="detalhe-equipamento.html?c=${x.c}">Ver detalhe</a>`;
    if (U.p == 'a' && x.st != 'i') b += ` <a class="btn-neutro" href="cadastros.html?e=${x.c}">Editar</a>`;
    if (U.p == 'g') b += x.st == 'd' ? ` <a class="btn-primario" href="nova-retirada.html?c=${x.c}">Solicitar retirada</a>` : (x.st == 'e' || x.st == 'a') ? ' <a class="btn-secundario" href="extensoes.html">Pedir extensão</a>' : ' <span class="btn-neutro" aria-disabled="true">Indisponível</span>';
    return `<div class="cartao card-eq${x.st == 'i' ? ' off' : ''}">${cod(x.c)}<h3>${x.n}</h3><p class="texto-ajuda">${CAT[x.k]} · ${SET[x.s][1]}</p>${sel(ST[x.st][0], ST[x.st][1])}${x.st == 'i' ? '<p class="texto-ajuda">Alerta de compra enviado à Diretoria.</p>' : ''}<div class="acoes">${b}</div></div>`;
  };
  return cab(`Catálogo · ${L.length} ativos${U.p == 'g' ? ' do setor' : ''}`, U.p == 'g' ? 'Equipamentos do meu setor' : 'Catálogo completo') + (U.p == 'a' ? '<p style="margin-bottom:14px"><a class="btn-primario" href="cadastros.html">+ Novo equipamento</a></p>' : '') + (U.p == 'd' ? '<div class="caixa-info msg">Visão somente leitura dos ' + IT.length + ' ativos.</div>' : '')
    + pills([['todos', 'Todas as categorias'], ...CAT.map((c, i) => [i, c])], X.f, 'cat') + (U.p == 'g' ? '' : pills([['', 'Todos os setores'], ...Object.keys(SET).map(k => [k, SET[k][1]])], X.s || '', 'set')) + `<div class="grade-cards">${L.map(card).join('')}</div>`;
};

R.detalhe = () => {
  const x = item(Q.get('c')); if (!x || (U.p == 'g' && x.s != U.s)) return cab('Catálogo', 'Equipamento não encontrado');
  const e = EMP[x.c], m = MAN.find(y => y.c == x.c), cp = COMPRA.find(y => y.it == x.c), xi = EXT.findIndex(y => y.it == x.c && y.st == 'p'), g = U.p, H = hist(x);
  const f = (l, t) => `<div><p class="rotulo-mono">${l}</p><b>${t}</b></div>`, car = (t, b) => `<div class="cartao pad"><p class="rotulo-mono">${t}</p>${b}</div>`;
  let topo = '', c1, c2 = '';
  if (e) {
    const xd = EXT.find(y => y.emp == e[4] && y.st != 'p'), ex = { n: 'Não utilizada', p: 'Pendente na Diretoria · nova data ' + (EXT[xi] ? EXT[xi].para : ''), u: xd ? 'Utilizada · ' + (xd.st == 'ok' ? 'concedida' : 'recusada') + ' em ' + xd.dec : 'Utilizada' }[e[2]];
    c1 = car('Empréstimo atual', `<div class="campos">${f('Setor solicitante', SET[x.s][1])}${f('Código do projeto / OS', e[0])}${f('Situação', sel(cor(e[3]), e[3]))}${f('Retirada', e[5])}${f('Prazo de devolução', e[6])}${f('Extensão de prazo', ex)}${f('Aprovado por', 'Almoxarifado')}</div>`);
    const t = { n: 'Nenhuma extensão pedida neste empréstimo. O pedido exige justificativa formal e passa pela Diretoria.', p: 'Pedido pendente na Diretoria para o dia ' + (EXT[xi] ? EXT[xi].para : '') + '.', u: 'Extensão já utilizada. Não é possível pedir outra neste empréstimo.' }[e[2]];
    c2 = car('Extensão de prazo · 1 por empréstimo', `<p>${t}</p><div class="acoes">${g == 'g' && e[2] == 'n' ? '<a class="btn-primario" href="extensoes.html">Solicitar extensão de prazo</a>' : ''}${g == 'd' && xi > -1 ? btn('Aprovar', 'ext-ok', xi, 'btn-primario') + ' ' + btn('Recusar', 'ext-no', xi) : ''}</div>`);
    if (g == 'a') topo = `<a class="btn-primario" href="registrar-devolucao.html?c=${x.c}">Registrar devolução</a>`;
  } else if (m) {
    c1 = car('Manutenção atual', `<div class="campos">${f('Motivo', m.motivo)}${f('Enviado em', m.dataf)}${f('Etapa', sel(m.et == 'c' ? 'verde' : 'amarelo', m.et == 'c' ? 'Reparo concluído' : 'Em reparo'))}</div>${g == 'a' && m.et == 'c' ? '<div class="acoes">' + btn('Validar recebimento', 'validar', m.c, 'btn-primario') + '</div>' : ''}`);
  } else if (x.st == 'i') {
    c1 = car('Descarte', `<div class="campos">${f('Motivo', cp ? cp.motivo : '—')}${f('Compra', cp && cp.st == 'a' ? 'Autorizada' : 'Aguardando a Diretoria')}</div>${g == 'd' && cp && cp.st == 'p' ? '<div class="acoes">' + btn('Autorizar compra', 'compra', x.c, 'btn-primario') + '</div>' : ''}`);
  } else {
    c1 = car('Empréstimo atual', '<p>Nenhum empréstimo em aberto.</p>');
    if (g == 'g') topo = `<a class="btn-primario" href="nova-retirada.html?c=${x.c}">Solicitar retirada</a>`;
  }
  const n = r => H.filter(h => r(h)).length, mini = (n, t) => `<div class="mini"><b>${n}</b><br>${t}</div>`;
  return `<p class="rotulo-mono migalhas"><a href="catalogo.html">Catálogo</a> / ${SET[x.s][0]} / ${x.n}</p>${cod(x.c)}
  <div class="linha" style="justify-content:space-between;align-items:flex-start;margin:10px 0 16px"><div><h1 style="font-size:28px;margin-bottom:8px">${x.n}</h1><div class="linha">${sel(ST[x.st][0], ST[x.st][1])}${sel('cinza', CAT[x.k])}${sel('cinza', SET[x.s][0])}</div></div>${topo}</div>
  <div class="det-grid"><div>${c1}${c2}</div><div>${car('Indicadores do equipamento', `<div class="minis">${mini(x.ne, 'empréstimos')}${mini(x.im, 'idas à manutenção')}${mini(x.rs, 'reposições simples')}${mini(x.xc, 'extensões concedidas')}</div>`)}
  ${car('Ficha', `${f('Categoria', CAT[x.k])}<br>${f('Setor vinculado', SET[x.s][0])}<br>${f('Disponibilidade', x.st == 'd' ? '1 / 1' : '0 / 1')}<br>${f('Uso principal', x.uso || '—')}`)}</div></div>
  <p class="rotulo-mono" style="margin:20px 0 8px">Histórico de movimentações</p>${tab(['Retirada', 'OS / projeto', 'Devolução', 'Destino na vistoria', 'Observações'], H.map(h => [h[0], cod(h[1]), h[2], sel(DS[h[3]][0], DS[h[3]][1]), h[4]]))}`;
};

R.emprestimos = () => {
  const L = vis().filter(x => EMP[x.c]).filter(x => X.f == 'todos' || (X.f == 'atr' ? x.st == 'a' : EMP[x.c][2] == 'p')), a = U.p == 'a';
  return cab(a ? 'Almoxarifado' : 'Meu setor', a ? 'Empréstimos ativos' : 'Meus empréstimos') + (a ? (IT.some(x => x.st == 'a') ? '<div class="caixa-info msg">Há empréstimos atrasados. Os setores continuam liberados para novas retiradas, mas a Diretoria acompanha cada atraso.</div>' : '') : '<div class="caixa-info msg">A devolução é feita em mãos ao Almoxarifado, que registra a vistoria.</div>')
    + pills([['todos', 'Todos'], ['atr', 'Atrasados'], ['ext', 'Extensão pendente']], X.f, 'filtro') + tab(['Item', ...(a ? ['Setor'] : []), 'OS', 'Prazo', 'Situação', ''], L.map(x => { const e = EMP[x.c]; return [cod(x.c) + '<br>' + x.n, ...(a ? [SET[x.s][1]] : []), e[0], e[1], sel(cor(e[3]), e[3]), a ? `<a class="btn-primario" href="registrar-devolucao.html?c=${x.c}">Registrar devolução</a>` : e[2] == 'n' ? '<a class="btn-neutro" href="extensoes.html">Pedir extensão</a>' : sel('cinza', e[2] == 'p' ? 'Extensão pendente' : 'Extensão usada')]; }));
};

R.solicitacoes = () => cab('Almoxarifado', 'Solicitações de retirada · ' + SOL.filter(x => x.st == 'p').length + ' pendentes') + (X.m ? `<div class="caixa-info msg">${X.m}</div>` : '') + tab(['Setor', 'Item', 'OS/Projeto', 'Prazo previsto', 'Situação'], SOL.map((x, i) => [SET[item(x.it).s][1], cod(x.it) + '<br>' + item(x.it).n, x.os, x.pz, x.st == 'p' ? (item(x.it).st == 'd' ? btn('Aprovar', 'aprovar', i, 'btn-primario') + ' ' + btn('Recusar', 'recusar', i) : sel('vermelho', 'Item indisponível')) : sel(x.st == 'ok' ? 'verde' : 'vermelho', x.st == 'ok' ? 'Aprovada' : 'Recusada')]));

R['nova-retirada'] = () => {
  const L = IT.filter(x => x.s == U.s), c = Q.get('c'); if (c && X.v[c] === undefined) X.v[c] = true;
  if (X.ok) return cab('Gestor', 'Nova retirada') + '<div class="caixa-info msg">Solicitação enviada ao Almoxarifado. O item só vira Emprestado depois da aprovação.</div>';
  return cab('Gestor · solicitação de retirada', 'Nova retirada') + (X.err ? `<div class="erro">${X.err}</div>` : '') + `<form id="f-ret" class="grade2"><div class="cartao pad"><p class="rotulo-mono">1 · Equipamentos do setor</p>${L.map(x => `<label class="linha-item"><input type="checkbox" name="${x.c}" ${x.st != 'd' ? 'disabled' : ''} ${X.v[x.c] ? 'checked' : ''}> <span>${x.n}<br>${cod(x.c)} ${sel(ST[x.st][0], ST[x.st][1])}</span></label>`).join('')}</div>
  <div class="cartao pad"><p class="rotulo-mono">2 · Projeto e prazo</p><div class="campo-form"><label>Código do projeto / OS *</label><input class="input-texto" name="codigo_os" placeholder="OS-2026-0440" value="${v('codigo_os')}"></div><div class="campo-form"><label>Prazo previsto de devolução *</label><input type="date" class="input-texto" name="prazo_devolucao" value="${v('prazo_devolucao')}"></div>
  <label class="linha"><input type="checkbox" name="aceite_termo" ${v('aceite_termo') ? 'checked' : ''}> <span class="texto-ajuda">Li e concordo com o termo digital de conservação e devolução no prazo.</span></label><p style="margin-top:14px"><button class="btn-primario" type="submit">Enviar ao Almoxarifado</button></p></div></form>`;
};

R.extensoes = () => {
  const meus = Object.keys(EMP).filter(c => item(c).s == U.s), lista = meus.filter(c => EMP[c][2] == 'n');
  return cab('Meus empréstimos · prorrogação', 'Solicitar extensão de prazo') + (X.m ? `<div class="caixa-info msg">${X.m}</div>` : '') + `<div class="grade2"><form id="f-ext" class="cartao pad"><div class="caixa-info" style="margin-bottom:14px">Só é permitida 1 extensão por empréstimo. O pedido passa pela aprovação da Diretoria.</div>
  ${lista.length ? `<div class="campo-form"><label>Empréstimo ativo *</label><select class="input-texto" name="emp">${lista.map(c => `<option value="${c}">${c} · ${item(c).n} · prazo ${EMP[c][1]}</option>`).join('')}</select></div><div class="campo-form"><label>Nova data pretendida *</label><input type="date" class="input-texto" name="nova" required></div><div class="campo-form"><label>Justificativa formal *</label><textarea class="input-texto" name="just" required></textarea></div><button class="btn-primario" type="submit">Enviar à Diretoria</button>` : '<p>Nenhum empréstimo disponível para extensão. <span class="texto-ajuda">Extensão já utilizada ou pendente.</span></p>'}</form>
  <div><p class="rotulo-mono" style="margin-bottom:8px">Histórico do setor</p>${tab(['Item', 'Situação'], meus.map(c => [item(c).n, sel({ n: 'cinza', p: 'amarelo', u: 'verde' }[EMP[c][2]], { n: 'Sem pedido', p: 'Pendente', u: 'Extensão já utilizada' }[EMP[c][2]])]))}</div></div>`;
};

R.aprovacoes = () => {
  const ex = EXT.map((x, i) => [item(x.it).n + '<br>' + SET[item(x.it).s][1] + ' · ' + EMP[x.it]?.[0], x.de + ' → ' + x.para, x.j, x.st == 'p' ? btn('Aprovar', 'ext-ok', i, 'btn-primario') + ' ' + btn('Recusar', 'ext-no', i) : sel(x.st == 'ok' ? 'verde' : 'vermelho', x.st == 'ok' ? 'Aprovada' : 'Recusada')]);
  const cp = COMPRA.map((x, i) => [item(x.it).n + '<br>' + cod(x.it), SET[item(x.it).s][1], x.motivo, x.st == 'p' ? btn('Autorizar compra', 'compra', x.it, 'btn-primario') : sel('verde', 'Compra autorizada')]);
  return cab('Diretoria · decisões pendentes', 'Aprovações') + (X.m ? `<div class="caixa-info msg">${X.m}</div>` : '') + pills([['x', 'Extensões de prazo'], ['c', 'Alertas de compra']], X.t, 'aba') + (X.t == 'x' ? tab(['Item / setor / OS', 'Prazo', 'Justificativa', ''], ex) : tab(['Item descartado', 'Setor', 'Motivo', ''], cp));
};

R.devolucao = () => {
  const c = Q.get('c') || '', x = item(c), e = EMP[c], d = +(X.v.dest || 1);
  if (X.ok) return cab('Almoxarifado', 'Devolução registrada') + `<div class="caixa-info msg">${x.n}: status final <b>${ST[x.st][1]}</b>. <a href="emprestimos.html">Voltar aos empréstimos</a></div>`;
  if (!x || !e) return cab('Almoxarifado', 'Registrar devolução') + '<div class="caixa-info">Escolha um empréstimo em <a href="emprestimos.html">Empréstimos</a>.</div>';
  const DD = [['Íntegro ou reposição simples', 'Volta para Disponível', 'Insumo reposto (opcional)'], ['Dano técnico ou quebra', 'Vai para a oficina de Manutenção', 'Defeito identificado *'], ['Perda total ou desgaste irreversível', 'Descarta e gera alerta de compra', 'Motivo do descarte *']];
  const fim = ['Disponível. O item volta ao catálogo do setor na hora.', 'Em manutenção. O item vai para a oficina e depois volta ao Almoxarifado.', 'Descartado. A Diretoria recebe um alerta de compra.'];
  return `<p class="rotulo-mono migalhas"><a href="emprestimos.html">Empréstimos</a> / ${c}</p>` + cab(SET[x.s][1] + ' · ' + e[0], 'Registrar devolução') + (X.err ? `<div class="erro">${X.err}</div>` : '') + `<div class="grade2"><div><div class="cartao pad"><p class="rotulo-mono">Empréstimo</p><p>${x.n} ${cod(c)}</p><p>Prazo: ${e[1]} · ${sel(cor(e[3]), e[3])}</p><p class="texto-ajuda">Condição na saída: íntegro. Devolução entregue em mãos pelo setor.</p></div>
  <div class="cartao pad" style="margin-top:16px"><p class="rotulo-mono">Checklist de conservação</p>${CK.map((t, i) => `<label class="linha-item"><input type="checkbox" name="k${i}" ${X.v['k' + i] !== false ? 'checked' : ''}> ${t}</label>`).join('')}</div></div>
  <form id="f-dev" class="cartao pad"><p class="rotulo-mono">Destino na vistoria *</p>${DD.map((t, i) => `<label class="opcao${d == i + 1 ? ' ativo' : ''}"><input type="radio" name="dest" value="${i + 1}" ${d == i + 1 ? 'checked' : ''}> <b>${i + 1} · ${t[0]}</b><br><span class="texto-ajuda">${t[1]}</span></label>`).join('')}
  <div class="campo-form"><label>${DD[d - 1][2]}</label><input class="input-texto" name="det" value="${v('det')}"></div><div class="campo-form"><label>Observação</label><textarea class="input-texto" name="obs">${v('obs')}</textarea></div>
  <div class="caixa-info" style="margin-bottom:14px"><b>Status final:</b> ${fim[d - 1]}</div><button class="btn-primario" type="submit">Confirmar devolução</button></form></div>`;
};

R.manutencao = () => {
  const of = U.p == 'g';
  return cab(of ? 'Oficina · Manutenção e Suporte' : 'Almoxarifado · itens fora da disponibilidade', of ? 'Oficina de manutenção' : 'Manutenção') + (X.m ? `<div class="caixa-info msg">${X.m}</div>` : '') + `<div class="linha" style="margin-bottom:16px">${['1 · Vistoria envia', '2 · Oficina repara', '3 · Almoxarifado valida', '4 · Disponível'].map(t => `<span class="filtro">${t}</span>`).join(' → ')}</div>`
    + tab(['Item', 'Motivo', 'Enviado em', 'Etapa', ''], MAN.map(m => [cod(m.c) + '<br>' + item(m.c).n, m.motivo, m.data, sel(m.et == 'of' ? 'amarelo' : 'verde', m.et == 'of' ? 'Em reparo' : 'Reparo concluído'), of ? (m.et == 'of' ? btn('Concluir reparo e devolver ao Almoxarifado', 'concluir', m.c, 'btn-primario') : sel('verde', 'Devolvido ao Almoxarifado')) : (m.et == 'c' ? btn('Validar recebimento', 'validar', m.c, 'btn-primario') : sel('amarelo', 'Na oficina'))]))
    + (of ? '<div class="cartao pad" style="margin-top:16px"><label class="rotulo-mono">Observação do reparo (ao concluir)</label><input class="input-texto" name="obs_reparo" value="' + v('obs_reparo') + '" placeholder="Ex.: substituída a porta Ethernet e testado o link"></div>' : '<p class="texto-ajuda" style="margin-top:12px">Ao validar o recebimento, o item volta a Disponível no catálogo do setor.</p>');
};

R.historico = () => {
  const aberto = Object.keys(EMP).map(c => ['—', c, EMP[c][0], EMP[c][1], EMP[c][3], cor(EMP[c][3])]);
  const L = [...aberto, ...HIS].filter(r => U.p != 'g' || item(r[1]).s == U.s);
  return cab(U.p == 'g' ? 'Movimentações do meu setor' : 'Todas as movimentações', 'Histórico de movimentações') + `<div class="linha" style="margin-bottom:14px">${U.p == 'g' ? '' : `<select class="input-texto" id="hs" style="width:200px"><option value="">Todos os setores</option>${Object.keys(SET).map(k => `<option value="${k}">${SET[k][1]}</option>`).join('')}</select>`}<input class="input-texto" id="hq" style="width:260px" placeholder="Item ou OS"></div>`
    + `<div class="cartao"><table class="tabela" id="ht"><thead><tr><th>Item</th><th>Setor</th><th>OS</th><th>Prazo / devolução</th><th>Situação / destino</th></tr></thead><tbody>${L.map(r => `<tr data-s="${item(r[1]).s}" data-t="${(r[1] + item(r[1]).n + r[2]).toLowerCase()}"><td>${cod(r[1])}<br>${item(r[1]).n}</td><td>${SET[item(r[1]).s][1]}</td><td>${r[2]}</td><td>${r[3]}</td><td>${sel(r[5], r[4])}</td></tr>`).join('')}</tbody></table></div>`;
};

R.cadastros = () => {
  const aba = pills([['x', 'Equipamentos'], ['c', 'Categorias'], ['u', 'Usuários e Setores']], X.t, 'aba'), ed = item(Q.get('e') || ''); let b;
  const op = (lista, sel_) => lista.map(([val, t]) => `<option value="${val}"${val == sel_ ? ' selected' : ''}>${t}</option>`).join('');
  if (X.t == 'x') {
    const val = (n, d) => X.v[n] !== undefined ? X.v[n] : (ed ? d : '');
    b = `<div class="grade2">${tab(['Código', 'Nome', 'Setor', 'Status', ''], IT.map(x => [cod(x.c), x.n, SET[x.s][1], sel(ST[x.st][0], ST[x.st][1]), x.st != 'i' ? `<a class="btn-neutro" href="cadastros.html?e=${x.c}">Editar</a>` : '']))}<form id="f-eq" class="cartao pad"><p class="rotulo-mono">${ed ? 'Editar equipamento' : 'Novo equipamento'}</p><div class="campo-form"><label>Nome *</label><input class="input-texto" name="nome" value="${val('nome', ed && ed.n)}"></div><div class="campo-form"><label>Categoria *</label><select class="input-texto" name="categoria_id">${op(CATS.map(c => [c.id, c.nome]), val('categoria_id', ed && ed.cid))}</select></div><div class="campo-form"><label>Setor vinculado *</label><select class="input-texto" name="setor_id">${op(Object.keys(SET).map(k => [SET[k][2], SET[k][0]]), val('setor_id', ed && SET[ed.s][2]))}</select></div><div class="campo-form"><label>Código de patrimônio *</label><input class="input-texto" id="cod" name="codigo" placeholder="NOTE-DEV-007" value="${val('codigo', ed && ed.c)}"><div class="erro" id="dup" style="display:none;margin-top:8px">Este código de patrimônio já está cadastrado.</div></div><div class="campo-form"><label>Condição inicial *</label><select class="input-texto" name="condicao">${op([['INTEGRO', 'Íntegro'], ['COM_MARCAS_DE_USO', 'Com marcas de uso']], val('condicao', ed && ed.cond))}</select></div><div class="campo-form"><label>Uso principal</label><input class="input-texto" name="uso" value="${val('uso', ed && ed.uso)}"></div><button class="btn-primario" type="submit">${ed ? 'Salvar alterações' : 'Salvar'}</button>${ed ? ' <a class="btn-neutro" href="cadastros.html">Cancelar</a>' : ''}</form></div>`;
  } else if (X.t == 'c') {
    b = `<div class="grade2">${tab(['Categoria', 'Itens', ''], CATS.map(c => [c.nome, c.itens, c.itens ? '<span class="texto-ajuda">Exclusão bloqueada: há itens</span>' : btn('Excluir', 'cat-del', c.id)]))}<form id="f-cat" class="cartao pad"><p class="rotulo-mono">Nova categoria</p><div class="campo-form"><label>Nome *</label><input class="input-texto" name="cat_nome" value="${v('cat_nome')}"></div><button class="btn-primario" type="submit">Salvar</button></form></div>`;
  } else {
    b = `<div class="grade2">${tab(['Nome', 'Perfil', 'Setor'], USR.map(u => [u[0] + (u[3] ? '' : ' <span class="texto-ajuda">(inativo)</span>'), u[1], u[2]]))}<form id="f-usr" class="cartao pad"><p class="rotulo-mono">Novo usuário</p><div class="campo-form"><label>Nome *</label><input class="input-texto" name="u_nome" value="${v('u_nome')}"></div><div class="campo-form"><label>E-mail *</label><input class="input-texto" type="email" name="u_email" value="${v('u_email')}"></div><div class="campo-form"><label>Senha inicial * (mín. 8 caracteres)</label><input class="input-texto" type="password" name="u_senha" autocomplete="new-password"></div><div class="campo-form"><label>Perfil *</label><select class="input-texto" id="uperf" name="u_perfil">${op([['g', 'Gestor'], ['a', 'Almoxarifado'], ['d', 'Diretoria']], v('u_perfil') || 'g')}</select></div><div class="campo-form" id="usetor"${(v('u_perfil') || 'g') == 'g' ? '' : ' style="display:none"'}><label>Setor *</label><select class="input-texto" name="u_setor">${op(Object.keys(SET).map(k => [SET[k][2], SET[k][0]]), v('u_setor'))}</select></div><button class="btn-primario" type="submit">Salvar</button></form></div>`;
  }
  return cab('Cadastros · somente Almoxarifado', 'Cadastros') + (X.m ? `<div class="caixa-info msg">${X.m}</div>` : '') + (X.err ? `<div class="erro">${X.err}</div>` : '') + aba + b;
};

R.setores = () => {
  const k = X.s || 'dev', L = nSet(k);
  return cab('Setores / perfil · centro de custo', SET[k][0]) + pills(Object.keys(SET).map(s => [s, SET[s][1]]), k, 'setor') + `<section class="indicadores">${ind('Equipamentos', L.length, 'vinculados')}${ind('Emprestados', L.filter(x => EMP[x.c]).length, 'agora')}${ind('Atrasos', L.filter(x => x.st == 'a').length, 'sem bloqueio do setor', 1)}${ind('Em manutenção', L.filter(x => x.st == 'm').length, 'agora')}</section>` + tab(['Equipamento', 'Status', 'OS atual'], L.map(x => [cod(x.c) + '<br>' + x.n, sel(ST[x.st][0], ST[x.st][1]), EMP[x.c] ? EMP[x.c][0] : '—']));
};

/* ---------- comunicação com o servidor ---------- */
// GET api.php?a=dados: tudo que a tela precisa, já filtrado pelo perfil do usuário logado
async function carregar() {
  const r = await fetch('api.php?a=dados', { headers: H, credentials: 'same-origin' });
  if (r.status == 401) { sessionStorage.removeItem('tr'); location = 'login.html'; throw new Error('Sessão expirada.'); }
  const d = await r.json().catch(() => null);
  if (!r.ok || !d || !d.ok) throw new Error((d && d.erro) || 'Não foi possível carregar os dados do banco.');
  U = { p: d.eu.p, s: d.eu.s }; sessionStorage.setItem('tr', JSON.stringify(U));
  SET = d.SET; CATS = d.CAT; CAT = d.CAT.map(c => c.nome);
  IT = d.IT; EMP = d.EMP; SOL = d.SOL; EXT = d.EXT; COMPRA = d.COMPRA; MAN = d.MAN; HIS = d.HIS; HD = d.HD; USR = d.USR; CK = d.CK; CKID = d.CKID;
}
// POST api.php?a=<ação>: grava no banco; lança erro com a mensagem das regras do banco (em português)
async function api(a, dados = {}) {
  const r = await fetch('api.php?a=' + a, { method: 'POST', headers: H, credentials: 'same-origin', body: new URLSearchParams(dados) });
  const d = await r.json().catch(() => null);
  if (r.status == 401) { sessionStorage.removeItem('tr'); location = 'login.html'; throw new Error('Sessão expirada.'); }
  if (!r.ok || !d || d.ok === false) throw new Error((d && d.erro) || 'Não foi possível concluir a operação.');
  return d;
}
const falha = msg => { if (P == 'nova-retirada' || P == 'devolucao' || P == 'cadastros') X.err = msg; else X.m = msg; };
const feito = async msg => { await carregar(); X.m = msg; };

/* ---------- ações (botões com data-a) ---------- */
const A = {
  perfil: i => { X.v.perfil = i; },
  cat: i => { X.f = i == 'todos' ? i : +i; }, set: i => { X.s = i; }, filtro: i => { X.f = i; }, aba: i => { X.t = i; X.err = ''; }, setor: i => { X.s = i; },
  aprovar: async i => { await api('aprovar', { id: SOL[i].id }); await feito('Retirada aprovada: o item agora está Emprestado.'); },
  recusar: async i => {
    const m = prompt('Motivo da recusa (o gestor poderá ver):'); if (m === null) return;
    await api('recusar', { id: SOL[i].id, motivo: m }); await feito('Retirada recusada.');
  },
  'ext-ok': async i => { await api('ext_decidir', { id: EXT[i].id, aprovar: 1 }); await feito('Extensão aprovada.'); },
  'ext-no': async i => { await api('ext_decidir', { id: EXT[i].id, aprovar: 0 }); await feito('Extensão recusada.'); },
  compra: async c => { await api('compra_autorizar', { id: COMPRA.find(x => x.it == c).id }); await feito('Compra autorizada.'); },
  concluir: async c => { await api('man_concluir', { id: MAN.find(x => x.c == c).id, obs: v('obs_reparo') }); X.v.obs_reparo = ''; await feito('Reparo concluído. Aguardando validação do Almoxarifado.'); },
  validar: async c => { await api('man_validar', { id: MAN.find(x => x.c == c).id }); await feito('Recebimento validado: item Disponível.'); },
  'cat-del': async id => { await api('cat_excluir', { id }); await feito('Categoria excluída.'); }
};
document.addEventListener('click', async e => {
  const b = e.target.closest('[data-a]'); if (!b) return;
  b.disabled = true;
  try { await A[b.dataset.a](b.dataset.i); } catch (err) { falha(err.message); }
  draw();
});
document.addEventListener('input', e => { const t = e.target; if (t.name) X.v[t.name] = t.type == 'checkbox' ? t.checked : t.value; if (t.id == 'setor') $('#email').value = MAIL[t.value] + '@techrental.com'; if (t.id == 'hq' || t.id == 'hs') filtrar(); if (t.id == 'cod') { const d = IT.some(x => x.c.toLowerCase() == t.value.trim().toLowerCase() && x.c != Q.get('e')); $('#dup').style.display = d ? 'block' : 'none'; } if (t.id == 'uperf') $('#usetor').style.display = t.value == 'g' ? '' : 'none'; if (t.name == 'dest') draw(); });
function filtrar() { const q = $('#hq').value.toLowerCase(), s = $('#hs') ? $('#hs').value : ''; document.querySelectorAll('#ht tbody tr').forEach(r => { r.style.display = (!q || r.dataset.t.includes(q)) && (!s || r.dataset.s == s) ? '' : 'none'; }); }
document.addEventListener('submit', async e => {
  e.preventDefault(); const f = e.target.id; X.err = '';
  if (f == 'f-login') { // valida e-mail e senha no servidor (login.php, que consulta o banco e abre a sessão)
    fetch('login.php', { method: 'POST', body: new URLSearchParams({ email: $('#email').value, senha: $('#senha').value }) })
      .then(r => r.ok ? r.json() : Promise.reject())
      .then(d => { if (!d.ok) throw 0; sessionStorage.setItem('tr', JSON.stringify({ p: d.p, s: d.s })); location = 'painel.html'; })
      .catch(() => { sessionStorage.removeItem('tr'); location.search = '?erro=1'; });
    return;
  }
  const btnEnviar = e.target.querySelector('[type=submit]'); if (btnEnviar) btnEnviar.disabled = true;
  try {
    if (f == 'f-ret') {
      const it = IT.filter(x => x.s == U.s && X.v[x.c]);
      if (!it.length) throw new Error('Selecione ao menos um equipamento.');
      await api('solicitar', { os: v('codigo_os').trim(), prazo: v('prazo_devolucao'), aceite: v('aceite_termo') ? 1 : 0, codigos: JSON.stringify(it.map(x => x.c)) });
      await carregar(); X.ok = 1;
    }
    if (f == 'f-ext') {
      const d = Object.fromEntries(new FormData(e.target)), c = d.emp;
      await api('ext_solicitar', { emprestimo_id: EMP[c][4], novo: d.nova, just: d.just });
      X.v = {}; await feito('Pedido enviado à Diretoria. Status: pendente.');
    }
    if (f == 'f-dev') {
      const c = Q.get('c'), d = +(X.v.dest || 1);
      if (d > 1 && !v('det').trim()) throw new Error('Informe o ' + (d == 2 ? 'defeito identificado.' : 'motivo do descarte.'));
      await api('devolver', { id: EMP[c][4], destino: d, detalhe: v('det'), obs: v('obs'), checklist: JSON.stringify(CKID.filter((id, i) => X.v['k' + i] !== false)) });
      await carregar(); X.ok = 1;
    }
    if (f == 'f-eq') {
      const ed = item(Q.get('e') || ''), d = { codigo: v('codigo') || (ed && ed.c) || '', nome: v('nome') || (ed && ed.n) || '', categoria_id: v('categoria_id') || (ed ? ed.cid : CATS[0].id), setor_id: v('setor_id') || (ed ? SET[ed.s][2] : SET[Object.keys(SET)[0]][2]), condicao: v('condicao') || (ed && ed.cond) || 'INTEGRO', uso: v('uso') !== '' ? v('uso') : (ed && ed.uso) || '' };
      await api(ed ? 'eq_atualizar' : 'eq_criar', ed ? { ...d, id: ed.id } : d);
      X.v = {}; await feito(ed ? 'Equipamento atualizado.' : 'Equipamento cadastrado.');
      if (ed) history.replaceState(null, '', 'cadastros.html');
    }
    if (f == 'f-cat') { await api('cat_criar', { nome: v('cat_nome') }); X.v = {}; await feito('Categoria cadastrada.'); }
    if (f == 'f-usr') {
      const p = v('u_perfil') || 'g';
      await api('usr_criar', { nome: v('u_nome'), email: v('u_email'), senha: new FormData(e.target).get('u_senha'), perfil: p, setor_id: p == 'g' ? (v('u_setor') || SET[Object.keys(SET)[0]][2]) : '' });
      X.v = {}; await feito('Usuário cadastrado.');
    }
  } catch (err) { falha(err.message); }
  draw();
});

/* ---------- desenha a página ---------- */
function draw() {
  const app = $('#app'); // redesenha o conteúdo inteiro
  if (P == 'login') { app.innerHTML = R.login(); return; }
  app.innerHTML = nav() + '<main class="conteudo">' + R[P]() + '</main>';
  $('#sair').onclick = () => { sessionStorage.removeItem('tr'); fetch('api.php?a=sair', { method: 'POST', headers: H, keepalive: true }); };
  X.m = '';
}
const permitida = () => MENU[U.p].some(m => m[1] == P) || P == 'detalhe' || (P == 'devolucao' && U.p == 'a') || (P == 'manutencao' && U.p == 'g' && U.s == 'ms');
if (P == 'login') draw();
else if (!U) location = 'login.html';
else {
  $('#app').innerHTML = '<main class="conteudo"><p class="texto-ajuda">Carregando dados do banco…</p></main>';
  carregar().then(() => { if (!permitida()) location = 'painel.html'; else draw(); })
    .catch(err => { if (U) $('#app').innerHTML = `<main class="conteudo"><div class="erro">${err.message}</div><p><a href="login.html">Voltar ao login</a></p></main>`; });
}
