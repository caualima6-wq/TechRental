<?php
// Conexão com o banco e sessão, compartilhadas por login.php e api.php.
//
// Se existir o init.php do projeto integrador (ele inicia a sessão e cria $pdo),
// ele é usado. Sem ele, a conexão é aberta pelas variáveis de ambiente do .env.

if (is_file(__DIR__ . '/init.php')) {
    require_once __DIR__ . '/init.php';
} else {
    $pegar = static function (array $nomes, string $padrao): string {
        foreach ($nomes as $n) {
            $v = getenv($n);
            if ($v !== false && $v !== '') {
                return $v;
            }
        }
        return $padrao;
    };
    $host  = $pegar(['DB_HOST', 'MYSQL_HOST'], 'db');
    $porta = $pegar(['DB_PORT', 'MYSQL_PORT'], '3306');
    $nome  = $pegar(['DB_NAME', 'MYSQL_DATABASE'], 'techrental');
    $user  = $pegar(['DB_USER', 'MYSQL_USER'], 'techrental');
    $senha = $pegar(['DB_PASSWORD', 'DB_PASS', 'MYSQL_PASSWORD'], '');

    $pdo = new PDO("mysql:host=$host;port=$porta;dbname=$nome;charset=utf8mb4", $user, $senha);
}

if (session_status() !== PHP_SESSION_ACTIVE) {
    session_set_cookie_params(['httponly' => true, 'samesite' => 'Lax']);
    session_start();
}

$pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
$pdo->setAttribute(PDO::ATTR_DEFAULT_FETCH_MODE, PDO::FETCH_ASSOC);
// O banco compara prazos com NOW(). Os prazos são em horário de Brasília (sem horário de verão),
// mas o MySQL de um container costuma estar em UTC. Alinhamos a sessão para o "atrasado" ficar certo.
$pdo->exec("SET time_zone = '-03:00'");
// O banco usa utf8mb4_0900_ai_ci; o driver PHP conecta por padrão com utf8mb4_general_ci, e as procedures
// que comparam texto falham com "Illegal mix of collations". Alinhamos a conexão com a do banco.
$pdo->exec("SET NAMES utf8mb4 COLLATE utf8mb4_0900_ai_ci");
date_default_timezone_set('America/Sao_Paulo');

/**
 * Chama uma procedure e devolve TODOS os conjuntos de resultado (as procedures de
 * "obter" devolvem mais de um SELECT). Erros de regra de negócio (SQLSTATE 45000)
 * viram ErroNegocio com a mensagem em português escrita no banco.
 */
class ErroNegocio extends RuntimeException {}

function chamar(PDO $pdo, string $proc, array $args = []): array
{
    $marcas = implode(',', array_fill(0, count($args), '?'));
    try {
        $st = $pdo->prepare("CALL $proc($marcas)");
        $st->execute($args);
        $conjuntos = [];
        do {
            if ($st->columnCount() > 0) {
                $conjuntos[] = $st->fetchAll();
            }
        } while ($st->nextRowset());
        $st->closeCursor();
        return $conjuntos;
    } catch (PDOException $e) {
        if (($e->errorInfo[0] ?? '') === '45000') {
            throw new ErroNegocio($e->errorInfo[2] ?? 'Operação não permitida.');
        }
        throw $e;
    }
}
