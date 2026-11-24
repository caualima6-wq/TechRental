<?php
// Login do TechRental: confere e-mail e senha no banco (procedure sp_usuario_login)
// e abre a sessão PHP. O perfil e o setor passam a vir da sessão do servidor.
// p = perfil: a Almoxarifado, g Gestor, d Diretoria · s = sigla do setor do gestor
// Para trocar uma senha: php -r "echo password_hash('NOVA_SENHA', PASSWORD_DEFAULT);"

header('Content-Type: application/json; charset=utf-8');
header('Cache-Control: no-store');

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    http_response_code(405);
    echo json_encode(['ok' => false]);
    exit;
}

require_once __DIR__ . '/conexao.php';

$email = strtolower(trim((string)($_POST['email'] ?? '')));
$senha = (string)($_POST['senha'] ?? '');

try {
    $u = chamar($pdo, 'sp_usuario_login', [$email])[0][0] ?? null;
} catch (Throwable $e) {
    error_log('login: ' . $e->getMessage());
    http_response_code(500);
    echo json_encode(['ok' => false, 'erro' => 'Banco de dados indisponível.']);
    exit;
}

// Roda o password_verify mesmo se o e-mail não existir (o tempo de resposta não revela nada).
$hash = $u['senha_hash'] ?? '$2y$10$usesomesillystringforsalt.abcdefghijklmnopqrstuv';
$ok = password_verify($senha, $hash) && $u !== null;

if (!$ok) {
    usleep(400000); // dificulta tentativa em massa
    http_response_code(401);
    echo json_encode(['ok' => false]);
    exit;
}

session_regenerate_id(true);
$_SESSION['uid'] = (int)$u['id'];
chamar($pdo, 'sp_usuario_registrar_login', [$u['id']]);

echo json_encode(['ok' => true, 'p' => $u['p'], 's' => $u['s']]);
