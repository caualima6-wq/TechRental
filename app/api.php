<?php
// API do TechRental. Todas as telas conversam com o banco por aqui.
//   GET  api.php?a=dados   -> tudo que as telas precisam, já filtrado pelo perfil
//   POST api.php?a=<ação>  -> ações (aprovar, devolver, cadastrar...)
// O usuário vem SEMPRE da sessão PHP (aberta no login.php), nunca de um id enviado pelo navegador.
// O banco ainda confere o perfil dentro das procedures; aqui repetimos a conferência por segurança.

require_once __DIR__ . '/conexao.php';

header('Content-Type: application/json; charset=utf-8');
header('Cache-Control: no-store');

function responder(array $d, int $codigo = 200): never
{
    http_response_code($codigo);
    echo json_encode($d, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES | JSON_INVALID_UTF8_SUBSTITUTE);
    exit;
}

function data(?string $s, string $f = 'd/m'): string
{
    return $s ? date($f, strtotime($s)) : '—';
}

$acao = $_GET['a'] ?? '';
$post = $_SERVER['REQUEST_METHOD'] === 'POST';

// Proteção contra CSRF: cabeçalho personalizado que outro site não consegue enviar.
if ($post && ($_SERVER['HTTP_X_TR'] ?? '') !== '1') {
    responder(['ok' => false, 'erro' => 'Requisição inválida.'], 403);
}

// ---- usuário da sessão (relido do banco a cada chamada: se foi desativado, perde o acesso) ----
$eu = null;
if (!empty($_SESSION['uid'])) {
    $st = $pdo->prepare("SELECT u.id, u.nome, u.perfil, u.setor_id, COALESCE(s.sigla,'') AS sigla
                           FROM usuarios u LEFT JOIN setores s ON s.id = u.setor_id
                          WHERE u.id = ? AND u.ativo = 1");
    $st->execute([$_SESSION['uid']]);
    $eu = $st->fetch() ?: null;
}

if ($acao === 'sair') {
    $_SESSION = [];
    session_destroy();
    responder(['ok' => true]);
}
if (!$eu) {
    responder(['ok' => false, 'erro' => 'Sessão expirada.'], 401);
}
$perfil = ['ALMOXARIFADO' => 'a', 'GESTOR' => 'g', 'DIRETORIA' => 'd'][$eu['perfil']];
$uid = (int)$eu['id'];

function exigir(string ...$perfis): void
{
    global $perfil;
    if (!in_array($perfil, $perfis, true)) {
        responder(['ok' => false, 'erro' => 'Seu perfil não tem permissão para esta ação.'], 403);
    }
}
function campo(string $n): string
{
    return trim((string)($_POST[$n] ?? ''));
}

try {
    if (!$post && $acao === 'dados') {
        responder(dados($pdo, $eu, $perfil));
    }
    if (!$post) {
        responder(['ok' => false, 'erro' => 'Ação desconhecida.'], 404);
    }

    switch ($acao) {
        // ---------- Gestor ----------
        case 'solicitar':
            exigir('g');
            $codigos = json_decode(campo('codigos'), true);
            if (!is_array($codigos)) {
                $codigos = [];
            }
            chamar($pdo, 'sp_emprestimo_solicitar', [
                campo('os'), $uid, json_encode(array_values($codigos)), campo('prazo') ?: null, (int)campo('aceite'),
            ]);
            break;
        case 'ext_solicitar':
            exigir('g');
            chamar($pdo, 'sp_extensao_solicitar', [(int)campo('emprestimo_id'), $uid, campo('novo') ?: null, campo('just')]);
            break;
        case 'man_concluir':
            exigir('g');
            chamar($pdo, 'sp_manutencao_concluir', [(int)campo('id'), $uid, campo('obs')]);
            break;

        // ---------- Almoxarifado ----------
        case 'aprovar':
            exigir('a');
            chamar($pdo, 'sp_emprestimo_aprovar', [(int)campo('id'), $uid]);
            break;
        case 'recusar':
            exigir('a');
            chamar($pdo, 'sp_emprestimo_recusar', [(int)campo('id'), $uid, campo('motivo')]);
            break;
        case 'devolver':
            exigir('a');
            $destino = ['1' => 'DISPONIVEL', '2' => 'MANUTENCAO', '3' => 'DESCARTE'][campo('destino')] ?? '';
            $lista = json_decode(campo('checklist'), true);
            chamar($pdo, 'sp_emprestimo_registrar_devolucao', [
                (int)campo('id'), $uid, $destino, campo('detalhe'), campo('obs'),
                json_encode(array_map('intval', is_array($lista) ? $lista : [])),
            ]);
            break;
        case 'man_validar':
            exigir('a');
            chamar($pdo, 'sp_manutencao_validar', [(int)campo('id'), $uid]);
            break;

        // ---------- Diretoria ----------
        case 'ext_decidir':
            exigir('d');
            chamar($pdo, 'sp_extensao_decidir', [(int)campo('id'), $uid, (int)campo('aprovar') === 1 ? 1 : 0]);
            break;
        case 'compra_autorizar':
            exigir('d');
            chamar($pdo, 'sp_compra_autorizar', [(int)campo('id'), $uid]);
            break;

        // ---------- Cadastros (somente Almoxarifado) ----------
        case 'eq_criar':
            exigir('a');
            chamar($pdo, 'sp_equipamento_criar', [
                campo('codigo'), campo('nome'), (int)campo('categoria_id'), (int)campo('setor_id'),
                campo('condicao') ?: 'INTEGRO', campo('uso') ?: null,
            ]);
            break;
        case 'eq_atualizar':
            exigir('a');
            chamar($pdo, 'sp_equipamento_atualizar', [
                (int)campo('id'), campo('codigo'), campo('nome'), (int)campo('categoria_id'), (int)campo('setor_id'),
                campo('condicao') ?: 'INTEGRO', campo('uso') ?: null,
            ]);
            break;
        case 'cat_criar':
            exigir('a');
            chamar($pdo, 'sp_categoria_criar', [campo('nome')]);
            break;
        case 'cat_excluir':
            exigir('a');
            chamar($pdo, 'sp_categoria_excluir', [(int)campo('id')]);
            break;
        case 'usr_criar':
            exigir('a');
            $senha = (string)($_POST['senha'] ?? '');
            if (strlen($senha) < 8) {
                throw new ErroNegocio('A senha precisa ter ao menos 8 caracteres.');
            }
            $perfilNovo = ['a' => 'ALMOXARIFADO', 'g' => 'GESTOR', 'd' => 'DIRETORIA'][campo('perfil')] ?? '';
            chamar($pdo, 'sp_usuario_criar', [
                campo('nome'), campo('email'), password_hash($senha, PASSWORD_DEFAULT),
                $perfilNovo, $perfilNovo === 'GESTOR' ? (int)campo('setor_id') : null,
            ]);
            break;

        default:
            responder(['ok' => false, 'erro' => 'Ação desconhecida.'], 404);
    }
    responder(['ok' => true]);
} catch (ErroNegocio $e) {
    responder(['ok' => false, 'erro' => $e->getMessage()], 422);
} catch (Throwable $e) {
    error_log('api.php [' . $acao . ']: ' . $e->getMessage());
    responder(['ok' => false, 'erro' => 'Erro ao acessar o banco de dados.'], 500);
}

/* ---------------------------------------------------------------------------
   Monta tudo que o app.js precisa, no mesmo formato dos dados do protótipo.
   Gestor só recebe o que é do próprio setor (a Oficina, do setor Suporte,
   também recebe os itens que estão em manutenção).
   --------------------------------------------------------------------------- */
function dados(PDO $pdo, array $eu, string $perfil): array
{
    $gestor = $perfil === 'g';
    $sid = $gestor ? (int)$eu['setor_id'] : null;
    $oficina = $gestor && $eu['sigla'] === 'ms';

    // setores e categorias
    $SET = [];
    $setores = $pdo->query('SELECT id, sigla, nome, nome_curto FROM setores WHERE ativo = 1 ORDER BY id')->fetchAll();
    foreach ($setores as $s) {
        $SET[$s['sigla']] = [$s['nome'], $s['nome_curto'], (int)$s['id']];
    }
    $categorias = $pdo->query('SELECT c.id, c.nome, COUNT(q.id) AS itens
                                 FROM categorias c LEFT JOIN equipamentos q ON q.categoria_id = c.id
                                GROUP BY c.id, c.nome ORDER BY c.id')->fetchAll();
    $catIndice = [];
    foreach ($categorias as $i => $c) {
        $catIndice[(int)$c['id']] = $i;
    }
    $CAT = array_map(fn($c) => ['id' => (int)$c['id'], 'nome' => $c['nome'], 'itens' => (int)$c['itens']], $categorias);

    // equipamentos (+ indicadores do detalhe)
    $sql = 'SELECT v.*,
              (SELECT COUNT(*) FROM emprestimos e WHERE e.equipamento_id = v.id AND e.status IN (\'ATIVO\',\'DEVOLVIDO\')) AS ne,
              (SELECT COUNT(*) FROM manutencoes m WHERE m.equipamento_id = v.id) AS im,
              (SELECT COUNT(*) FROM vw_historico h WHERE h.equipamento_id = v.id AND h.destino_vistoria = \'REPOSICAO_SIMPLES\') AS rs,
              (SELECT COUNT(*) FROM extensoes_prazo x JOIN emprestimos e ON e.id = x.emprestimo_id
                WHERE e.equipamento_id = v.id AND x.status = \'APROVADA\') AS xc
            FROM vw_equipamentos v';
    $args = [];
    if ($gestor) {
        $sql .= ' WHERE v.setor_id = ?' . ($oficina ? ' OR v.id IN (SELECT equipamento_id FROM manutencoes WHERE etapa <> \'VALIDADA\')' : '');
        $args[] = $sid;
    }
    $st = $pdo->prepare($sql . ' ORDER BY v.codigo_patrimonio');
    $st->execute($args);
    $mapaStatus = ['DISPONIVEL' => 'd', 'EMPRESTADO' => 'e', 'ATRASADO' => 'a', 'MANUTENCAO' => 'm', 'DESCARTADO' => 'i'];
    $IT = [];
    $codigos = [];
    foreach ($st->fetchAll() as $q) {
        $codigos[$q['codigo_patrimonio']] = true;
        $IT[] = [
            'id' => (int)$q['id'], 'c' => $q['codigo_patrimonio'], 'n' => $q['nome'],
            'k' => $catIndice[(int)$q['categoria_id']] ?? 0, 's' => $q['setor_sigla'],
            'st' => $mapaStatus[$q['status']] ?? 'd', 'uso' => $q['uso_principal'] ?? '',
            'cond' => $q['condicao_inicial'], 'cid' => (int)$q['categoria_id'],
            'ne' => (int)$q['ne'], 'im' => (int)$q['im'], 'rs' => (int)$q['rs'], 'xc' => (int)$q['xc'],
        ];
    }
    $meu = fn(string $codigo) => isset($codigos[$codigo]);

    // empréstimos em aberto: código -> [OS, prazo, extensão n|p|u, situação, id, retirada, prazo completo]
    $EMP = [];
    $sql = 'SELECT * FROM vw_emprestimos_ativos' . ($gestor ? ' WHERE setor_id = ?' : '') . ' ORDER BY retirado_em';
    $st = $pdo->prepare($sql);
    $st->execute($gestor ? [$sid] : []);
    $ext = ['NAO_UTILIZADA' => 'n', 'PENDENTE' => 'p', 'UTILIZADA' => 'u'];
    foreach ($st->fetchAll() as $e) {
        $EMP[$e['codigo_patrimonio']] = [
            $e['codigo_os'], data($e['prazo_devolucao']), $ext[$e['extensao_status']], $e['situacao_prazo'],
            (int)$e['emprestimo_id'], data($e['retirado_em'], 'd/m/Y H:i'), data($e['prazo_devolucao'], 'd/m/Y H:i'),
        ];
    }

    // solicitações pendentes
    $SOL = [];
    if ($perfil !== 'd') {
        foreach ($pdo->query('SELECT * FROM vw_solicitacoes_pendentes')->fetchAll() as $s) {
            if ($meu($s['codigo_patrimonio'])) {
                $SOL[] = ['id' => (int)$s['emprestimo_id'], 'it' => $s['codigo_patrimonio'], 'os' => $s['codigo_os'],
                          'pz' => data($s['prazo_previsto']), 'st' => 'p'];
            }
        }
    }

    // extensões (todas; pendentes primeiro)
    $EXT = [];
    $rows = chamar($pdo, 'sp_extensao_listar', [null, $sid])[0] ?? [];
    $stExt = ['PENDENTE' => 'p', 'APROVADA' => 'ok', 'RECUSADA' => 'no'];
    foreach ($rows as $x) {
        $EXT[] = ['id' => (int)$x['extensao_id'], 'emp' => (int)$x['emprestimo_id'], 'it' => $x['codigo_patrimonio'],
                  'de' => data($x['prazo_atual']), 'para' => data($x['novo_prazo']), 'j' => $x['justificativa'],
                  'st' => $stExt[$x['status']], 'dec' => data($x['decidido_em'], 'd/m/Y')];
    }
    usort($EXT, fn($a, $b) => ($a['st'] !== 'p') <=> ($b['st'] !== 'p'));

    // alertas de compra
    $COMPRA = [];
    foreach ($pdo->query('SELECT * FROM vw_alertas_compra ORDER BY criado_em')->fetchAll() as $c) {
        if ($perfil !== 'g' || $meu($c['codigo_patrimonio'])) {
            $COMPRA[] = ['id' => (int)$c['alerta_id'], 'it' => $c['codigo_patrimonio'], 'motivo' => $c['motivo'],
                         'st' => $c['status'] === 'PENDENTE' ? 'p' : 'a'];
        }
    }

    // manutenção em aberto
    $MAN = [];
    foreach (chamar($pdo, 'sp_manutencao_listar', [null])[0] ?? [] as $m) {
        if (!$gestor || $oficina || $meu($m['codigo_patrimonio'])) {
            $MAN[] = ['id' => (int)$m['manutencao_id'], 'c' => $m['codigo_patrimonio'], 'motivo' => $m['motivo'],
                      'data' => data($m['enviado_em']), 'dataf' => data($m['enviado_em'], 'd/m/Y'),
                      'et' => $m['etapa'] === 'EM_REPARO' ? 'of' : 'c'];
        }
    }

    // histórico: HIS (devolvidos, para a tela Histórico) e HD (tudo, para o detalhe do equipamento)
    $HIS = [];
    $HD = [];
    $chave = ['ABERTO' => 'open', 'INTEGRO' => 'ok', 'REPOSICAO_SIMPLES' => 'rep', 'MANUTENCAO' => 'man', 'DESCARTADO' => 'des'];
    $rotulo = ['INTEGRO' => ['Íntegro', 'verde'], 'REPOSICAO_SIMPLES' => ['Reposição simples', 'verde'],
               'MANUTENCAO' => ['Manutenção', 'amarelo'], 'DESCARTADO' => ['Descartado', 'cinza']];
    $padrao = ['ABERTO' => 'Em uso pelo setor.', 'INTEGRO' => 'Conferido, sem avarias.',
               'REPOSICAO_SIMPLES' => 'Faltou acessório básico. Reposto pelo Almoxarifado.',
               'MANUTENCAO' => 'Falha técnica. Enviado à oficina de Manutenção.', 'DESCARTADO' => 'Perda total. Item descartado.'];
    foreach (chamar($pdo, 'sp_historico_listar', [$sid, null])[0] ?? [] as $h) {
        $d = $h['destino_vistoria'];
        $HD[] = [$h['codigo_patrimonio'], data($h['retirado_em'], 'd/m H:i'), $h['codigo_os'],
                 $h['devolvido_em'] ? data($h['devolvido_em'], 'd/m H:i') : '—', $chave[$d], $h['observacao'] ?: $padrao[$d]];
        if ($d !== 'ABERTO') {
            $HIS[] = [data($h['retirado_em']), $h['codigo_patrimonio'], $h['codigo_os'], data($h['devolvido_em']), $rotulo[$d][0], $rotulo[$d][1]];
        }
    }

    // usuários (só o Almoxarifado vê) e checklist da vistoria
    $USR = [];
    if ($perfil === 'a') {
        $nomePerfil = ['ALMOXARIFADO' => 'Almoxarifado', 'GESTOR' => 'Gestor', 'DIRETORIA' => 'Diretoria'];
        foreach (chamar($pdo, 'sp_usuario_listar', [null, null, 0])[0] ?? [] as $u) {
            $USR[] = [$u['nome'], $nomePerfil[$u['perfil']], $u['setor'] ?: '—', (int)$u['ativo']];
        }
    }
    $ck = $pdo->query('SELECT id, descricao FROM checklist_itens WHERE ativo = 1 ORDER BY ordem, id')->fetchAll();

    return [
        'ok' => true, 'eu' => ['p' => $perfil, 's' => $eu['sigla'], 'nome' => $eu['nome']],
        'SET' => $SET, 'CAT' => $CAT, 'IT' => $IT, 'EMP' => (object)$EMP, 'SOL' => $SOL, 'EXT' => $EXT,
        'COMPRA' => $COMPRA, 'MAN' => $MAN, 'HIS' => $HIS, 'HD' => $HD, 'USR' => $USR,
        'CK' => array_column($ck, 'descricao'), 'CKID' => array_map('intval', array_column($ck, 'id')),
    ];
}
