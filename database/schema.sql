<<<<<<< HEAD
-- =====================================================================
-- TechRental · banco de dados MySQL 8.0+ (8.0.16 ou superior por causa dos CHECK)
-- 01 · Estrutura: tabelas, restrições, triggers e funções auxiliares
-- =====================================================================
-- Regras do negócio que o banco garante (vindas do protótipo):
--   * 3 perfis: Almoxarifado, Gestor (sempre ligado a 1 setor) e Diretoria
--   * 4 setores e 4 categorias de equipamento
--   * Só equipamento DISPONÍVEL pode ser solicitado
--   * Cada equipamento tem no máximo 1 empréstimo ATIVO por vez
--   * Cada empréstimo aceita no máximo 1 pedido de extensão de prazo
--   * Cada equipamento tem no máximo 1 manutenção em aberto
--   * Atraso NÃO bloqueia o setor (por isso não existe nenhuma trava de atraso)
--   * Devolução: Disponível / Manutenção / Descarte (descarte gera alerta de compra)
-- "ATRASADO" não é gravado: é calculado nas views (prazo vencido + empréstimo ativo),
-- assim o status nunca fica desatualizado.
-- =====================================================================

-- ATENÇÃO: a linha abaixo APAGA o banco 'techrental' inteiro e recria do zero.
-- Serve para o ambiente de desenvolvimento; remova-a antes de usar com dados reais.
DROP DATABASE IF EXISTS techrental;
CREATE DATABASE techrental
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_0900_ai_ci;
USE techrental;

SET NAMES utf8mb4;

-- ---------------------------------------------------------------------
-- Cadastros básicos
-- ---------------------------------------------------------------------
CREATE TABLE setores (
  id          INT UNSIGNED NOT NULL AUTO_INCREMENT,
  sigla       VARCHAR(10)  NOT NULL,              -- dev, pd, cp, ms (mesmas chaves do app.js)
  nome        VARCHAR(80)  NOT NULL,
  nome_curto  VARCHAR(30)  NOT NULL,
  ativo       TINYINT(1)   NOT NULL DEFAULT 1,
  criado_em   DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_setores_sigla (sigla),
  UNIQUE KEY uq_setores_nome (nome)
) ENGINE=InnoDB;

CREATE TABLE categorias (
  id          INT UNSIGNED NOT NULL AUTO_INCREMENT,
  nome        VARCHAR(60)  NOT NULL,
  criado_em   DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_categorias_nome (nome)
) ENGINE=InnoDB;

CREATE TABLE usuarios (
  id             INT UNSIGNED NOT NULL AUTO_INCREMENT,
  nome           VARCHAR(100) NOT NULL,
  email          VARCHAR(120) NOT NULL,
  senha_hash     VARCHAR(255) NOT NULL,            -- bcrypt gerado por password_hash() do PHP
  perfil         ENUM('ALMOXARIFADO','GESTOR','DIRETORIA') NOT NULL,
  setor_id       INT UNSIGNED NULL,                -- obrigatório só para GESTOR
  ativo          TINYINT(1)   NOT NULL DEFAULT 1,
  ultimo_login   DATETIME     NULL,
  criado_em      DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  atualizado_em  DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_usuarios_email (email),
  KEY ix_usuarios_setor (setor_id),
  CONSTRAINT fk_usuarios_setor FOREIGN KEY (setor_id) REFERENCES setores (id),
  CONSTRAINT ck_usuarios_email_minusculo CHECK (email = LOWER(email)),
  CONSTRAINT ck_usuarios_perfil_setor CHECK (
       (perfil = 'GESTOR' AND setor_id IS NOT NULL)
    OR (perfil <> 'GESTOR' AND setor_id IS NULL))
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- Equipamentos (patrimônio)
-- ---------------------------------------------------------------------
CREATE TABLE equipamentos (
  id                  INT UNSIGNED NOT NULL AUTO_INCREMENT,
  codigo_patrimonio   VARCHAR(20)  NOT NULL,       -- ex.: NOTE-DEV-001
  nome                VARCHAR(120) NOT NULL,
  categoria_id        INT UNSIGNED NOT NULL,
  setor_id            INT UNSIGNED NOT NULL,       -- setor vinculado (dono do equipamento)
  status              ENUM('DISPONIVEL','EMPRESTADO','MANUTENCAO','DESCARTADO')
                      NOT NULL DEFAULT 'DISPONIVEL',
  condicao_inicial    ENUM('INTEGRO','COM_MARCAS_DE_USO') NOT NULL DEFAULT 'INTEGRO',
  uso_principal       VARCHAR(255) NULL,
  criado_em           DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  atualizado_em       DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_equip_codigo (codigo_patrimonio),
  KEY ix_equip_categoria (categoria_id),
  KEY ix_equip_setor_status (setor_id, status),
  CONSTRAINT fk_equip_categoria FOREIGN KEY (categoria_id) REFERENCES categorias (id),
  CONSTRAINT fk_equip_setor     FOREIGN KEY (setor_id)     REFERENCES setores (id)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- Empréstimos: 1 linha por equipamento. Vários equipamentos pedidos juntos
-- na "Nova retirada" compartilham o mesmo codigo_os.
-- Ciclo: PENDENTE -> ATIVO -> DEVOLVIDO   (ou PENDENTE -> RECUSADO / CANCELADO)
-- ---------------------------------------------------------------------
CREATE TABLE emprestimos (
  id               INT UNSIGNED NOT NULL AUTO_INCREMENT,
  codigo_os        VARCHAR(20)  NOT NULL,          -- ex.: OS-2026-0412
  equipamento_id   INT UNSIGNED NOT NULL,
  setor_id         INT UNSIGNED NOT NULL,          -- setor que retirou (foto do momento)
  solicitante_id   INT UNSIGNED NOT NULL,          -- gestor que pediu
  status           ENUM('PENDENTE','ATIVO','RECUSADO','CANCELADO','DEVOLVIDO')
                   NOT NULL DEFAULT 'PENDENTE',
  aceite_termo     TINYINT(1)   NOT NULL,          -- termo digital de conservação
  solicitado_em    DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  prazo_original   DATETIME     NOT NULL,
  prazo_devolucao  DATETIME     NOT NULL,          -- muda quando uma extensão é aprovada
  analisado_por    INT UNSIGNED NULL,              -- almoxarife que aprovou/recusou
  analisado_em     DATETIME     NULL,
  motivo_recusa    VARCHAR(255) NULL,
  retirado_em      DATETIME     NULL,
  devolvido_em     DATETIME     NULL,
  -- Trava "1 empréstimo ativo por equipamento" (UNIQUE ignora NULL)
  ativo_unico      INT UNSIGNED GENERATED ALWAYS AS
                   (CASE WHEN status = 'ATIVO' THEN equipamento_id END) VIRTUAL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_emp_ativo_por_equip (ativo_unico),
  KEY ix_emp_os (codigo_os),
  KEY ix_emp_equip (equipamento_id),
  KEY ix_emp_setor_status (setor_id, status),
  KEY ix_emp_status_prazo (status, prazo_devolucao),
  CONSTRAINT fk_emp_equip       FOREIGN KEY (equipamento_id) REFERENCES equipamentos (id),
  CONSTRAINT fk_emp_setor       FOREIGN KEY (setor_id)       REFERENCES setores (id),
  CONSTRAINT fk_emp_solicitante FOREIGN KEY (solicitante_id) REFERENCES usuarios (id),
  CONSTRAINT fk_emp_analisado   FOREIGN KEY (analisado_por)  REFERENCES usuarios (id),
  CONSTRAINT ck_emp_termo CHECK (aceite_termo = 1),
  CONSTRAINT ck_emp_prazo CHECK (prazo_original > solicitado_em AND prazo_devolucao >= prazo_original),
  CONSTRAINT ck_emp_ativo_tem_retirada CHECK (status NOT IN ('ATIVO','DEVOLVIDO') OR retirado_em IS NOT NULL)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- Extensão de prazo: no máximo 1 pedido por empréstimo (UNIQUE em emprestimo_id).
-- Recusada também conta como "utilizada", igual ao protótipo.
-- ---------------------------------------------------------------------
CREATE TABLE extensoes_prazo (
  id               INT UNSIGNED NOT NULL AUTO_INCREMENT,
  emprestimo_id    INT UNSIGNED NOT NULL,
  solicitante_id   INT UNSIGNED NOT NULL,
  prazo_atual      DATETIME     NOT NULL,
  novo_prazo       DATETIME     NOT NULL,
  justificativa    VARCHAR(500) NOT NULL,           -- justificativa formal obrigatória
  status           ENUM('PENDENTE','APROVADA','RECUSADA') NOT NULL DEFAULT 'PENDENTE',
  solicitado_em    DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  decidido_por     INT UNSIGNED NULL,               -- diretor
  decidido_em      DATETIME     NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_ext_um_por_emprestimo (emprestimo_id),
  KEY ix_ext_status (status),
  CONSTRAINT fk_ext_emprestimo   FOREIGN KEY (emprestimo_id)  REFERENCES emprestimos (id),
  CONSTRAINT fk_ext_solicitante  FOREIGN KEY (solicitante_id) REFERENCES usuarios (id),
  CONSTRAINT fk_ext_decidido     FOREIGN KEY (decidido_por)   REFERENCES usuarios (id),
  CONSTRAINT ck_ext_prazo CHECK (novo_prazo > prazo_atual),
  CONSTRAINT ck_ext_justificativa CHECK (CHAR_LENGTH(TRIM(justificativa)) > 0)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- Devolução (vistoria feita pelo Almoxarifado, em mãos)
-- ---------------------------------------------------------------------
CREATE TABLE checklist_itens (
  id         INT UNSIGNED NOT NULL AUTO_INCREMENT,
  descricao  VARCHAR(80)  NOT NULL,
  ordem      TINYINT UNSIGNED NOT NULL DEFAULT 0,
  ativo      TINYINT(1)   NOT NULL DEFAULT 1,
  PRIMARY KEY (id),
  UNIQUE KEY uq_checklist_desc (descricao)
) ENGINE=InnoDB;

CREATE TABLE devolucoes (
  id              INT UNSIGNED NOT NULL AUTO_INCREMENT,
  emprestimo_id   INT UNSIGNED NOT NULL,
  recebido_por    INT UNSIGNED NOT NULL,            -- almoxarife
  devolvido_em    DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  destino         ENUM('DISPONIVEL','MANUTENCAO','DESCARTE') NOT NULL,
  -- DISPONIVEL: insumo reposto (opcional) · MANUTENCAO: defeito · DESCARTE: motivo
  detalhe         VARCHAR(255) NULL,
  observacao      VARCHAR(500) NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_dev_emprestimo (emprestimo_id),
  KEY ix_dev_destino (destino),
  CONSTRAINT fk_dev_emprestimo FOREIGN KEY (emprestimo_id) REFERENCES emprestimos (id),
  CONSTRAINT fk_dev_recebido   FOREIGN KEY (recebido_por)  REFERENCES usuarios (id),
  CONSTRAINT ck_dev_detalhe CHECK (destino = 'DISPONIVEL' OR CHAR_LENGTH(TRIM(COALESCE(detalhe,''))) > 0)
) ENGINE=InnoDB;

CREATE TABLE devolucao_checklist (
  devolucao_id       INT UNSIGNED NOT NULL,
  checklist_item_id  INT UNSIGNED NOT NULL,
  conferido          TINYINT(1)   NOT NULL DEFAULT 1,
  PRIMARY KEY (devolucao_id, checklist_item_id),
  CONSTRAINT fk_dc_devolucao FOREIGN KEY (devolucao_id) REFERENCES devolucoes (id) ON DELETE CASCADE,
  CONSTRAINT fk_dc_item      FOREIGN KEY (checklist_item_id) REFERENCES checklist_itens (id)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- Manutenção: vistoria envia -> oficina repara -> almoxarifado valida -> Disponível
-- ---------------------------------------------------------------------
CREATE TABLE manutencoes (
  id               INT UNSIGNED NOT NULL AUTO_INCREMENT,
  equipamento_id   INT UNSIGNED NOT NULL,
  devolucao_id     INT UNSIGNED NULL,               -- de qual devolução veio (se veio)
  motivo           VARCHAR(255) NOT NULL,
  etapa            ENUM('EM_REPARO','REPARO_CONCLUIDO','VALIDADA') NOT NULL DEFAULT 'EM_REPARO',
  enviado_em       DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  observacao_reparo VARCHAR(500) NULL,
  concluido_por    INT UNSIGNED NULL,               -- gestor do Suporte (oficina)
  concluido_em     DATETIME     NULL,
  validado_por     INT UNSIGNED NULL,               -- almoxarife
  validado_em      DATETIME     NULL,
  -- Trava "1 manutenção em aberto por equipamento"
  aberta_unica     INT UNSIGNED GENERATED ALWAYS AS
                   (CASE WHEN etapa <> 'VALIDADA' THEN equipamento_id END) VIRTUAL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_man_aberta_por_equip (aberta_unica),
  KEY ix_man_equip (equipamento_id),
  KEY ix_man_etapa (etapa),
  CONSTRAINT fk_man_equip     FOREIGN KEY (equipamento_id) REFERENCES equipamentos (id),
  CONSTRAINT fk_man_devolucao FOREIGN KEY (devolucao_id)   REFERENCES devolucoes (id),
  CONSTRAINT fk_man_concluido FOREIGN KEY (concluido_por)  REFERENCES usuarios (id),
  CONSTRAINT fk_man_validado  FOREIGN KEY (validado_por)   REFERENCES usuarios (id)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- Alerta de compra (gerado quando um item é descartado; a Diretoria autoriza)
-- ---------------------------------------------------------------------
CREATE TABLE alertas_compra (
  id               INT UNSIGNED NOT NULL AUTO_INCREMENT,
  equipamento_id   INT UNSIGNED NOT NULL,
  devolucao_id     INT UNSIGNED NULL,
  motivo           VARCHAR(255) NOT NULL,
  status           ENUM('PENDENTE','AUTORIZADA') NOT NULL DEFAULT 'PENDENTE',
  criado_em        DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  autorizado_por   INT UNSIGNED NULL,               -- diretor
  autorizado_em    DATETIME     NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_compra_equip (equipamento_id),
  KEY ix_compra_status (status),
  CONSTRAINT fk_compra_equip     FOREIGN KEY (equipamento_id) REFERENCES equipamentos (id),
  CONSTRAINT fk_compra_devolucao FOREIGN KEY (devolucao_id)   REFERENCES devolucoes (id),
  CONSTRAINT fk_compra_autorizou FOREIGN KEY (autorizado_por) REFERENCES usuarios (id)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- Funções auxiliares (usadas no seed e nas procedures)
-- ---------------------------------------------------------------------
DELIMITER $$

CREATE FUNCTION fn_equipamento_id(p_codigo VARCHAR(20)) RETURNS INT UNSIGNED
READS SQL DATA
BEGIN
  RETURN (SELECT id FROM equipamentos WHERE codigo_patrimonio = UPPER(TRIM(p_codigo)));
END$$

CREATE FUNCTION fn_usuario_id(p_email VARCHAR(120)) RETURNS INT UNSIGNED
READS SQL DATA
BEGIN
  RETURN (SELECT id FROM usuarios WHERE email = LOWER(TRIM(p_email)));
END$$

CREATE FUNCTION fn_setor_id(p_sigla VARCHAR(10)) RETURNS INT UNSIGNED
READS SQL DATA
BEGIN
  RETURN (SELECT id FROM setores WHERE sigla = LOWER(TRIM(p_sigla)));
END$$

-- ---------------------------------------------------------------------
-- Triggers: protegem as regras mesmo se alguém escrever SQL direto no banco
-- ---------------------------------------------------------------------

-- Só equipamento DISPONÍVEL pode ser solicitado, e o gestor só pede item do próprio setor
CREATE TRIGGER trg_emprestimos_bi BEFORE INSERT ON emprestimos
FOR EACH ROW
BEGIN
  DECLARE v_status VARCHAR(20);
  DECLARE v_setor_equip INT UNSIGNED;
  DECLARE v_perfil VARCHAR(20);
  DECLARE v_setor_user INT UNSIGNED;

  IF NEW.status = 'PENDENTE' THEN
    SELECT status, setor_id INTO v_status, v_setor_equip
      FROM equipamentos WHERE id = NEW.equipamento_id;
    IF v_status <> 'DISPONIVEL' THEN
      SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Equipamento indisponível para retirada.';
    END IF;
    SELECT perfil, setor_id INTO v_perfil, v_setor_user
      FROM usuarios WHERE id = NEW.solicitante_id;
    IF v_perfil <> 'GESTOR' OR v_setor_user <> v_setor_equip THEN
      SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Somente o gestor do setor pode solicitar equipamentos do próprio setor.';
    END IF;
    SET NEW.setor_id = v_setor_equip;
  END IF;
END$$

-- Extensão só para empréstimo ATIVO, pedida por gestor do setor dono do empréstimo
CREATE TRIGGER trg_extensoes_bi BEFORE INSERT ON extensoes_prazo
FOR EACH ROW
BEGIN
  DECLARE v_status VARCHAR(20);
  DECLARE v_setor INT UNSIGNED;
  DECLARE v_prazo DATETIME;
  DECLARE v_setor_user INT UNSIGNED;

  SELECT status, setor_id, prazo_devolucao INTO v_status, v_setor, v_prazo
    FROM emprestimos WHERE id = NEW.emprestimo_id;
  IF v_status <> 'ATIVO' THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Só é possível pedir extensão de um empréstimo ativo.';
  END IF;
  SELECT setor_id INTO v_setor_user FROM usuarios WHERE id = NEW.solicitante_id AND perfil = 'GESTOR';
  IF v_setor_user IS NULL OR v_setor_user <> v_setor THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Somente o gestor do setor pode pedir extensão deste empréstimo.';
  END IF;
  SET NEW.prazo_atual = v_prazo;
END$$

-- Decisões de extensão e autorização de compra são exclusivas da Diretoria
CREATE TRIGGER trg_extensoes_bu BEFORE UPDATE ON extensoes_prazo
FOR EACH ROW
BEGIN
  IF NEW.status <> OLD.status AND OLD.status <> 'PENDENTE' THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Esta extensão já foi decidida e não pode ser alterada.';
  END IF;
  IF NEW.status <> 'PENDENTE' AND NOT EXISTS
     (SELECT 1 FROM usuarios WHERE id = NEW.decidido_por AND perfil = 'DIRETORIA' AND ativo = 1) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Somente a Diretoria pode decidir extensões de prazo.';
  END IF;
END$$

CREATE TRIGGER trg_alertas_compra_bu BEFORE UPDATE ON alertas_compra
FOR EACH ROW
BEGIN
  IF NEW.status = 'AUTORIZADA' AND OLD.status = 'PENDENTE' AND NOT EXISTS
     (SELECT 1 FROM usuarios WHERE id = NEW.autorizado_por AND perfil = 'DIRETORIA' AND ativo = 1) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Somente a Diretoria pode autorizar compras.';
  END IF;
END$$

-- Devolução e validação só pelo Almoxarifado
CREATE TRIGGER trg_devolucoes_bi BEFORE INSERT ON devolucoes
FOR EACH ROW
BEGIN
  IF NOT EXISTS (SELECT 1 FROM usuarios WHERE id = NEW.recebido_por AND perfil = 'ALMOXARIFADO' AND ativo = 1) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Somente o Almoxarifado registra devoluções.';
  END IF;
END$$

DELIMITER ;
-- =====================================================================
-- TechRental · 02 · Views (cada uma alimenta uma tela do sistema)
-- =====================================================================
USE techrental;
SET NAMES utf8mb4;

-- Situação do prazo exatamente como aparece nas telas: "No prazo", "Devolve hoje",
-- "Devolve amanhã" e "Atrasado: N dias"
-- (dias contados por data, não por hora: vencer às 18h de hoje ainda é "Devolve hoje")

-- ---- Empréstimos ativos (telas Empréstimos / Meus empréstimos / Painel) ----
CREATE OR REPLACE VIEW vw_emprestimos_ativos AS
SELECT
  e.id                    AS emprestimo_id,
  e.codigo_os,
  q.id                    AS equipamento_id,
  q.codigo_patrimonio,
  q.nome                  AS equipamento,
  s.id                    AS setor_id,
  s.sigla                 AS setor_sigla,
  s.nome_curto            AS setor,
  u.nome                  AS solicitante,
  e.retirado_em,
  e.prazo_original,
  e.prazo_devolucao,
  (e.prazo_devolucao < NOW())                          AS atrasado,
  CASE
    WHEN DATE(e.prazo_devolucao) < CURDATE() THEN CONCAT('Atrasado: ', DATEDIFF(CURDATE(), DATE(e.prazo_devolucao)),
                                                         IF(DATEDIFF(CURDATE(), DATE(e.prazo_devolucao)) = 1, ' dia', ' dias'))
    WHEN DATE(e.prazo_devolucao) = CURDATE() THEN IF(e.prazo_devolucao < NOW(), 'Atrasado: hoje', 'Devolve hoje')
    WHEN DATE(e.prazo_devolucao) = CURDATE() + INTERVAL 1 DAY THEN 'Devolve amanhã'
    ELSE 'No prazo'
  END                                                  AS situacao_prazo,
  CASE x.status
    WHEN 'PENDENTE'  THEN 'PENDENTE'
    WHEN 'APROVADA'  THEN 'UTILIZADA'
    WHEN 'RECUSADA'  THEN 'UTILIZADA'
    ELSE 'NAO_UTILIZADA'
  END                                                  AS extensao_status,
  x.id                    AS extensao_id,
  x.novo_prazo            AS extensao_novo_prazo
FROM emprestimos e
JOIN equipamentos q   ON q.id = e.equipamento_id
JOIN setores s        ON s.id = e.setor_id
JOIN usuarios u       ON u.id = e.solicitante_id
LEFT JOIN extensoes_prazo x ON x.emprestimo_id = e.id
WHERE e.status = 'ATIVO';

-- ---- Catálogo (status "ATRASADO" é calculado aqui) ----
CREATE OR REPLACE VIEW vw_equipamentos AS
SELECT
  q.id,
  q.codigo_patrimonio,
  q.nome,
  c.id           AS categoria_id,
  c.nome         AS categoria,
  s.id           AS setor_id,
  s.sigla        AS setor_sigla,
  s.nome         AS setor,
  s.nome_curto   AS setor_curto,
  q.status       AS status_base,
  CASE WHEN a.emprestimo_id IS NOT NULL AND a.atrasado = 1 THEN 'ATRASADO' ELSE q.status END AS status,
  q.condicao_inicial,
  q.uso_principal,
  a.emprestimo_id,
  a.codigo_os    AS os_atual,
  a.prazo_devolucao,
  a.situacao_prazo,
  a.extensao_status,
  q.criado_em,
  q.atualizado_em
FROM equipamentos q
JOIN categorias c ON c.id = q.categoria_id
JOIN setores s    ON s.id = q.setor_id
LEFT JOIN vw_emprestimos_ativos a ON a.equipamento_id = q.id;

-- ---- Solicitações pendentes (tela Solicitações do Almoxarifado) ----
CREATE OR REPLACE VIEW vw_solicitacoes_pendentes AS
SELECT
  e.id            AS emprestimo_id,
  e.codigo_os,
  s.nome_curto    AS setor,
  q.codigo_patrimonio,
  q.nome          AS equipamento,
  q.status        AS status_equipamento,
  (q.status = 'DISPONIVEL') AS pode_aprovar,
  u.nome          AS solicitante,
  e.solicitado_em,
  e.prazo_devolucao AS prazo_previsto
FROM emprestimos e
JOIN equipamentos q ON q.id = e.equipamento_id
JOIN setores s      ON s.id = e.setor_id
JOIN usuarios u     ON u.id = e.solicitante_id
WHERE e.status = 'PENDENTE'
ORDER BY e.solicitado_em;

-- ---- Extensões pendentes (Aprovações > Extensões de prazo) ----
CREATE OR REPLACE VIEW vw_extensoes_pendentes AS
SELECT
  x.id            AS extensao_id,
  e.id            AS emprestimo_id,
  e.codigo_os,
  q.codigo_patrimonio,
  q.nome          AS equipamento,
  s.nome_curto    AS setor,
  x.prazo_atual,
  x.novo_prazo,
  x.justificativa,
  u.nome          AS solicitante,
  x.solicitado_em
FROM extensoes_prazo x
JOIN emprestimos e  ON e.id = x.emprestimo_id
JOIN equipamentos q ON q.id = e.equipamento_id
JOIN setores s      ON s.id = e.setor_id
JOIN usuarios u     ON u.id = x.solicitante_id
WHERE x.status = 'PENDENTE' AND e.status = 'ATIVO'
ORDER BY x.solicitado_em;

-- ---- Alertas de compra (Aprovações > Alertas de compra) ----
CREATE OR REPLACE VIEW vw_alertas_compra AS
SELECT
  a.id            AS alerta_id,
  q.codigo_patrimonio,
  q.nome          AS equipamento,
  s.nome_curto    AS setor,
  a.motivo,
  a.status,
  a.criado_em,
  a.autorizado_em,
  u.nome          AS autorizado_por
FROM alertas_compra a
JOIN equipamentos q ON q.id = a.equipamento_id
JOIN setores s      ON s.id = q.setor_id
LEFT JOIN usuarios u ON u.id = a.autorizado_por;

-- ---- Manutenção (Almoxarifado e Oficina do Gestor de Suporte) ----
CREATE OR REPLACE VIEW vw_manutencoes AS
SELECT
  m.id            AS manutencao_id,
  q.codigo_patrimonio,
  q.nome          AS equipamento,
  s.nome_curto    AS setor,
  m.motivo,
  m.etapa,
  m.enviado_em,
  m.observacao_reparo,
  m.concluido_em,
  m.validado_em
FROM manutencoes m
JOIN equipamentos q ON q.id = m.equipamento_id
JOIN setores s      ON s.id = q.setor_id;

-- ---- Histórico de movimentações (tela Histórico e aba do detalhe do equipamento) ----
-- Destino na vistoria: ABERTO, INTEGRO, REPOSICAO_SIMPLES, MANUTENCAO, DESCARTADO
CREATE OR REPLACE VIEW vw_historico AS
SELECT
  e.id                AS emprestimo_id,
  q.id                AS equipamento_id,
  q.codigo_patrimonio,
  q.nome              AS equipamento,
  s.id                AS setor_id,
  s.sigla             AS setor_sigla,
  s.nome_curto        AS setor,
  e.codigo_os,
  e.retirado_em,
  e.prazo_devolucao,
  e.devolvido_em,
  CASE
    WHEN e.status = 'ATIVO'                        THEN 'ABERTO'
    WHEN d.destino = 'MANUTENCAO'                  THEN 'MANUTENCAO'
    WHEN d.destino = 'DESCARTE'                    THEN 'DESCARTADO'
    WHEN d.detalhe IS NOT NULL AND TRIM(d.detalhe) <> '' THEN 'REPOSICAO_SIMPLES'
    ELSE 'INTEGRO'
  END                 AS destino_vistoria,
  d.observacao,
  e.status            AS status_emprestimo
FROM emprestimos e
JOIN equipamentos q ON q.id = e.equipamento_id
JOIN setores s      ON s.id = e.setor_id
LEFT JOIN devolucoes d ON d.emprestimo_id = e.id
WHERE e.status IN ('ATIVO','DEVOLVIDO');

-- ---- Indicadores por setor (Painel da Diretoria, tela Setores, painel do Gestor) ----
CREATE OR REPLACE VIEW vw_indicadores_setor AS
SELECT
  s.id                                                            AS setor_id,
  s.sigla,
  s.nome,
  s.nome_curto,
  COUNT(q.id)                                                     AS equipamentos,
  COALESCE(SUM(q.status = 'EMPRESTADO'), 0)                       AS emprestados,
  COALESCE(SUM(q.status = 'EMPRESTADO' AND a.atrasado = 1), 0)    AS atrasados,
  COALESCE(SUM(q.status = 'MANUTENCAO'), 0)                       AS em_manutencao,
  COALESCE(SUM(q.status = 'DESCARTADO'), 0)                       AS descartados,
  COALESCE(SUM(q.status = 'DISPONIVEL'), 0)                       AS disponiveis
FROM setores s
LEFT JOIN equipamentos q ON q.setor_id = s.id
LEFT JOIN vw_emprestimos_ativos a ON a.equipamento_id = q.id
GROUP BY s.id, s.sigla, s.nome, s.nome_curto;

-- ---- Indicadores gerais (Painel do Almoxarifado e da Diretoria) ----
CREATE OR REPLACE VIEW vw_indicadores_gerais AS
SELECT
  (SELECT COUNT(*) FROM equipamentos)                                      AS ativos_registrados,
  (SELECT COUNT(*) FROM equipamentos WHERE status = 'DESCARTADO')          AS descartados,
  (SELECT COUNT(*) FROM emprestimos WHERE status = 'ATIVO')                AS emprestados,
  (SELECT COUNT(*) FROM vw_emprestimos_ativos WHERE atrasado = 1)          AS atrasados,
  (SELECT COUNT(*) FROM emprestimos WHERE status = 'PENDENTE')             AS solicitacoes_pendentes,
  (SELECT COUNT(*) FROM manutencoes WHERE etapa <> 'VALIDADA')             AS manutencoes_abertas,
  (SELECT COUNT(*) FROM manutencoes WHERE etapa = 'REPARO_CONCLUIDO')      AS manutencoes_a_validar,
  (SELECT COUNT(*) FROM extensoes_prazo x JOIN emprestimos e ON e.id = x.emprestimo_id
    WHERE x.status = 'PENDENTE' AND e.status = 'ATIVO')                    AS extensoes_pendentes,
  (SELECT COUNT(*) FROM alertas_compra WHERE status = 'PENDENTE')          AS compras_pendentes;
-- =====================================================================
-- TechRental · 03 · Procedures de CRUD e de fluxo
-- Convenção: sp_<entidade>_<criar|listar|obter|atualizar|excluir> + ações de fluxo.
-- Erros de regra de negócio saem como SQLSTATE '45000' com mensagem em português,
-- pronta para o PHP mostrar ao usuário. Toda mudança de status roda em transação.
-- =====================================================================
USE techrental;
SET NAMES utf8mb4;
DELIMITER $$

CREATE FUNCTION fn_usuario_tem_perfil(p_id INT UNSIGNED, p_perfil VARCHAR(20)) RETURNS TINYINT(1)
READS SQL DATA
BEGIN
  RETURN EXISTS (SELECT 1 FROM usuarios WHERE id = p_id AND perfil = p_perfil AND ativo = 1);
END$$

-- =====================================================================
-- SETORES
-- =====================================================================
CREATE PROCEDURE sp_setor_criar(IN p_sigla VARCHAR(10), IN p_nome VARCHAR(80), IN p_nome_curto VARCHAR(30))
BEGIN
  DECLARE EXIT HANDLER FOR 1062 SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Já existe um setor com esta sigla ou este nome.';
  IF TRIM(COALESCE(p_sigla,'')) = '' OR TRIM(COALESCE(p_nome,'')) = '' OR TRIM(COALESCE(p_nome_curto,'')) = '' THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Informe sigla, nome e nome curto do setor.';
  END IF;
  INSERT INTO setores (sigla, nome, nome_curto) VALUES (LOWER(TRIM(p_sigla)), TRIM(p_nome), TRIM(p_nome_curto));
  SELECT LAST_INSERT_ID() AS id;
END$$

CREATE PROCEDURE sp_setor_listar(IN p_apenas_ativos TINYINT(1))
BEGIN
  SELECT s.*, (SELECT COUNT(*) FROM equipamentos q WHERE q.setor_id = s.id) AS equipamentos
    FROM setores s
   WHERE p_apenas_ativos IS NULL OR p_apenas_ativos = 0 OR s.ativo = 1
   ORDER BY s.nome;
END$$

CREATE PROCEDURE sp_setor_obter(IN p_id INT UNSIGNED)
BEGIN
  SELECT * FROM vw_indicadores_setor WHERE setor_id = p_id;
END$$

CREATE PROCEDURE sp_setor_atualizar(IN p_id INT UNSIGNED, IN p_sigla VARCHAR(10), IN p_nome VARCHAR(80),
                                    IN p_nome_curto VARCHAR(30), IN p_ativo TINYINT(1))
BEGIN
  DECLARE EXIT HANDLER FOR 1062 SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Já existe um setor com esta sigla ou este nome.';
  IF NOT EXISTS (SELECT 1 FROM setores WHERE id = p_id) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Setor não encontrado.';
  END IF;
  UPDATE setores SET sigla = LOWER(TRIM(p_sigla)), nome = TRIM(p_nome), nome_curto = TRIM(p_nome_curto), ativo = p_ativo
   WHERE id = p_id;
  CALL sp_setor_obter(p_id);
END$$

CREATE PROCEDURE sp_setor_excluir(IN p_id INT UNSIGNED)
BEGIN
  IF NOT EXISTS (SELECT 1 FROM setores WHERE id = p_id) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Setor não encontrado.';
  END IF;
  IF EXISTS (SELECT 1 FROM equipamentos WHERE setor_id = p_id) OR EXISTS (SELECT 1 FROM usuarios WHERE setor_id = p_id) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Exclusão bloqueada: há equipamentos ou usuários neste setor. Desative o setor.';
  END IF;
  DELETE FROM setores WHERE id = p_id;
END$$

-- =====================================================================
-- CATEGORIAS  (exclusão bloqueada quando há itens, como mostra a aba Categorias)
-- =====================================================================
CREATE PROCEDURE sp_categoria_criar(IN p_nome VARCHAR(60))
BEGIN
  DECLARE EXIT HANDLER FOR 1062 SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Já existe uma categoria com este nome.';
  IF TRIM(COALESCE(p_nome,'')) = '' THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Informe o nome da categoria.';
  END IF;
  INSERT INTO categorias (nome) VALUES (TRIM(p_nome));
  SELECT LAST_INSERT_ID() AS id;
END$$

CREATE PROCEDURE sp_categoria_listar()
BEGIN
  SELECT c.id, c.nome, COUNT(q.id) AS itens, (COUNT(q.id) = 0) AS pode_excluir
    FROM categorias c LEFT JOIN equipamentos q ON q.categoria_id = c.id
   GROUP BY c.id, c.nome ORDER BY c.id;
END$$

CREATE PROCEDURE sp_categoria_obter(IN p_id INT UNSIGNED)
BEGIN
  SELECT c.id, c.nome, COUNT(q.id) AS itens
    FROM categorias c LEFT JOIN equipamentos q ON q.categoria_id = c.id
   WHERE c.id = p_id GROUP BY c.id, c.nome;
END$$

CREATE PROCEDURE sp_categoria_atualizar(IN p_id INT UNSIGNED, IN p_nome VARCHAR(60))
BEGIN
  DECLARE EXIT HANDLER FOR 1062 SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Já existe uma categoria com este nome.';
  IF NOT EXISTS (SELECT 1 FROM categorias WHERE id = p_id) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Categoria não encontrada.';
  END IF;
  UPDATE categorias SET nome = TRIM(p_nome) WHERE id = p_id;
  CALL sp_categoria_obter(p_id);
END$$

CREATE PROCEDURE sp_categoria_excluir(IN p_id INT UNSIGNED)
BEGIN
  IF NOT EXISTS (SELECT 1 FROM categorias WHERE id = p_id) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Categoria não encontrada.';
  END IF;
  IF EXISTS (SELECT 1 FROM equipamentos WHERE categoria_id = p_id) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Exclusão bloqueada: há itens nesta categoria.';
  END IF;
  DELETE FROM categorias WHERE id = p_id;
END$$

-- =====================================================================
-- USUÁRIOS  (a senha chega já como hash bcrypt: password_hash() no PHP)
-- =====================================================================
CREATE PROCEDURE sp_usuario_criar(IN p_nome VARCHAR(100), IN p_email VARCHAR(120), IN p_senha_hash VARCHAR(255),
                                  IN p_perfil VARCHAR(20), IN p_setor_id INT UNSIGNED)
BEGIN
  DECLARE EXIT HANDLER FOR 1062 SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Já existe um usuário com este e-mail.';
  DECLARE EXIT HANDLER FOR 3819 SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Perfil Gestor exige um setor; Almoxarifado e Diretoria não têm setor.';
  DECLARE EXIT HANDLER FOR 1452 SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Setor inexistente.';
  IF TRIM(COALESCE(p_nome,'')) = '' OR TRIM(COALESCE(p_email,'')) = '' OR COALESCE(p_senha_hash,'') = '' THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Informe nome, e-mail e senha.';
  END IF;
  IF p_perfil NOT IN ('ALMOXARIFADO','GESTOR','DIRETORIA') THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Perfil inválido.';
  END IF;
  INSERT INTO usuarios (nome, email, senha_hash, perfil, setor_id)
  VALUES (TRIM(p_nome), LOWER(TRIM(p_email)), p_senha_hash, p_perfil, p_setor_id);
  SELECT LAST_INSERT_ID() AS id;
END$$

CREATE PROCEDURE sp_usuario_listar(IN p_perfil VARCHAR(20), IN p_setor_id INT UNSIGNED, IN p_apenas_ativos TINYINT(1))
BEGIN
  SELECT u.id, u.nome, u.email, u.perfil, u.setor_id, s.nome_curto AS setor, u.ativo, u.ultimo_login
    FROM usuarios u LEFT JOIN setores s ON s.id = u.setor_id
   WHERE (p_perfil IS NULL OR u.perfil = p_perfil)
     AND (p_setor_id IS NULL OR u.setor_id = p_setor_id)
     AND (p_apenas_ativos IS NULL OR p_apenas_ativos = 0 OR u.ativo = 1)
   ORDER BY FIELD(u.perfil,'ALMOXARIFADO','GESTOR','DIRETORIA'), u.nome;
END$$

CREATE PROCEDURE sp_usuario_obter(IN p_id INT UNSIGNED)
BEGIN
  SELECT u.id, u.nome, u.email, u.perfil, u.setor_id, s.sigla AS setor_sigla, s.nome AS setor,
         u.ativo, u.ultimo_login, u.criado_em
    FROM usuarios u LEFT JOIN setores s ON s.id = u.setor_id WHERE u.id = p_id;
END$$

CREATE PROCEDURE sp_usuario_atualizar(IN p_id INT UNSIGNED, IN p_nome VARCHAR(100), IN p_email VARCHAR(120),
                                      IN p_perfil VARCHAR(20), IN p_setor_id INT UNSIGNED, IN p_ativo TINYINT(1))
BEGIN
  DECLARE EXIT HANDLER FOR 1062 SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Já existe um usuário com este e-mail.';
  DECLARE EXIT HANDLER FOR 3819 SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Perfil Gestor exige um setor; Almoxarifado e Diretoria não têm setor.';
  DECLARE EXIT HANDLER FOR 1452 SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Setor inexistente.';
  IF NOT EXISTS (SELECT 1 FROM usuarios WHERE id = p_id) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Usuário não encontrado.';
  END IF;
  UPDATE usuarios SET nome = TRIM(p_nome), email = LOWER(TRIM(p_email)), perfil = p_perfil,
                      setor_id = p_setor_id, ativo = p_ativo
   WHERE id = p_id;
  CALL sp_usuario_obter(p_id);
END$$

CREATE PROCEDURE sp_usuario_alterar_senha(IN p_id INT UNSIGNED, IN p_senha_hash VARCHAR(255))
BEGIN
  IF NOT EXISTS (SELECT 1 FROM usuarios WHERE id = p_id) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Usuário não encontrado.';
  END IF;
  UPDATE usuarios SET senha_hash = p_senha_hash WHERE id = p_id;
END$$

-- Substitui o array $usuarios do login.php: devolve o hash para o PHP rodar password_verify().
-- Se o e-mail não existe ou está inativo, devolve 0 linhas (o PHP usa o hash falso, como já faz hoje).
CREATE PROCEDURE sp_usuario_login(IN p_email VARCHAR(120))
BEGIN
  SELECT u.id, u.senha_hash,
         CASE u.perfil WHEN 'ALMOXARIFADO' THEN 'a' WHEN 'GESTOR' THEN 'g' ELSE 'd' END AS p,   -- mesmos códigos do app.js
         COALESCE(s.sigla, '') AS s
    FROM usuarios u LEFT JOIN setores s ON s.id = u.setor_id
   WHERE u.email = LOWER(TRIM(p_email)) AND u.ativo = 1;
END$$

CREATE PROCEDURE sp_usuario_registrar_login(IN p_id INT UNSIGNED)
BEGIN
  UPDATE usuarios SET ultimo_login = NOW() WHERE id = p_id;
END$$

CREATE PROCEDURE sp_usuario_excluir(IN p_id INT UNSIGNED)
BEGIN
  DECLARE EXIT HANDLER FOR 1451 SIGNAL SQLSTATE '45000'
    SET MESSAGE_TEXT = 'Exclusão bloqueada: o usuário tem movimentações no histórico. Desative o usuário.';
  IF NOT EXISTS (SELECT 1 FROM usuarios WHERE id = p_id) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Usuário não encontrado.';
  END IF;
  DELETE FROM usuarios WHERE id = p_id;
END$$

-- =====================================================================
-- EQUIPAMENTOS
-- =====================================================================
CREATE PROCEDURE sp_equipamento_criar(IN p_codigo VARCHAR(20), IN p_nome VARCHAR(120), IN p_categoria_id INT UNSIGNED,
                                      IN p_setor_id INT UNSIGNED, IN p_condicao VARCHAR(20), IN p_uso VARCHAR(255))
BEGIN
  DECLARE EXIT HANDLER FOR 1062 SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Este código de patrimônio já está cadastrado.';
  DECLARE EXIT HANDLER FOR 1452 SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Categoria ou setor inexistente.';
  IF TRIM(COALESCE(p_codigo,'')) = '' OR TRIM(COALESCE(p_nome,'')) = '' THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Informe o nome e o código de patrimônio.';
  END IF;
  INSERT INTO equipamentos (codigo_patrimonio, nome, categoria_id, setor_id, condicao_inicial, uso_principal)
  VALUES (UPPER(TRIM(p_codigo)), TRIM(p_nome), p_categoria_id, p_setor_id, COALESCE(p_condicao,'INTEGRO'), p_uso);
  SELECT LAST_INSERT_ID() AS id;
END$$

-- Todos os filtros são opcionais (NULL = sem filtro). p_status aceita também 'ATRASADO'.
CREATE PROCEDURE sp_equipamento_listar(IN p_categoria_id INT UNSIGNED, IN p_setor_id INT UNSIGNED,
                                       IN p_status VARCHAR(20), IN p_busca VARCHAR(100))
BEGIN
  SELECT * FROM vw_equipamentos
   WHERE (p_categoria_id IS NULL OR categoria_id = p_categoria_id)
     AND (p_setor_id IS NULL OR setor_id = p_setor_id)
     AND (p_status IS NULL OR status = p_status)
     AND (p_busca IS NULL OR p_busca = '' OR CONCAT_WS(' ', codigo_patrimonio, nome, os_atual) LIKE CONCAT('%', p_busca, '%'))
   ORDER BY codigo_patrimonio;
END$$

-- Tela de detalhe: 1) ficha  2) histórico de movimentações  3) indicadores
CREATE PROCEDURE sp_equipamento_obter(IN p_id INT UNSIGNED)
BEGIN
  SELECT * FROM vw_equipamentos WHERE id = p_id;
  SELECT * FROM vw_historico WHERE equipamento_id = p_id ORDER BY retirado_em DESC;
  SELECT
    (SELECT COUNT(*) FROM emprestimos WHERE equipamento_id = p_id AND status IN ('ATIVO','DEVOLVIDO')) AS emprestimos,
    (SELECT COUNT(*) FROM manutencoes WHERE equipamento_id = p_id)                                    AS idas_manutencao,
    (SELECT COUNT(*) FROM vw_historico WHERE equipamento_id = p_id AND destino_vistoria = 'REPOSICAO_SIMPLES') AS reposicoes_simples,
    (SELECT COUNT(*) FROM extensoes_prazo x JOIN emprestimos e ON e.id = x.emprestimo_id
      WHERE e.equipamento_id = p_id AND x.status = 'APROVADA')                                        AS extensoes_concedidas;
END$$

CREATE PROCEDURE sp_equipamento_obter_por_codigo(IN p_codigo VARCHAR(20))
BEGIN
  CALL sp_equipamento_obter(fn_equipamento_id(p_codigo));
END$$

-- Status NÃO é editável aqui: ele muda só pelas ações de fluxo (aprovar, devolver, manutenção...)
CREATE PROCEDURE sp_equipamento_atualizar(IN p_id INT UNSIGNED, IN p_codigo VARCHAR(20), IN p_nome VARCHAR(120),
                                          IN p_categoria_id INT UNSIGNED, IN p_setor_id INT UNSIGNED,
                                          IN p_condicao VARCHAR(20), IN p_uso VARCHAR(255))
BEGIN
  DECLARE v_status VARCHAR(20);
  DECLARE v_setor INT UNSIGNED;
  DECLARE EXIT HANDLER FOR 1062 SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Este código de patrimônio já está cadastrado.';
  DECLARE EXIT HANDLER FOR 1452 SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Categoria ou setor inexistente.';
  SELECT status, setor_id INTO v_status, v_setor FROM equipamentos WHERE id = p_id;
  IF v_status IS NULL THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Equipamento não encontrado.'; END IF;
  IF v_status = 'DESCARTADO' THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Equipamento descartado não pode ser editado.'; END IF;
  IF p_setor_id <> v_setor AND (v_status <> 'DISPONIVEL' OR EXISTS
       (SELECT 1 FROM emprestimos WHERE equipamento_id = p_id AND status = 'PENDENTE')) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Só é possível trocar o setor de um equipamento disponível e sem solicitação pendente.';
  END IF;
  UPDATE equipamentos
     SET codigo_patrimonio = UPPER(TRIM(p_codigo)), nome = TRIM(p_nome), categoria_id = p_categoria_id,
         setor_id = p_setor_id, condicao_inicial = p_condicao, uso_principal = p_uso
   WHERE id = p_id;
  SELECT * FROM vw_equipamentos WHERE id = p_id;
END$$

-- Só exclui cadastro feito por engano (sem nenhum histórico). Equipamento com histórico sai pelo DESCARTE.
CREATE PROCEDURE sp_equipamento_excluir(IN p_id INT UNSIGNED)
BEGIN
  DECLARE EXIT HANDLER FOR 1451 SIGNAL SQLSTATE '45000'
    SET MESSAGE_TEXT = 'Exclusão bloqueada: o equipamento tem histórico. Registre o descarte na devolução.';
  IF NOT EXISTS (SELECT 1 FROM equipamentos WHERE id = p_id) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Equipamento não encontrado.';
  END IF;
  DELETE FROM equipamentos WHERE id = p_id;
END$$

-- =====================================================================
-- EMPRÉSTIMOS · solicitar -> aprovar/recusar -> devolver
-- =====================================================================

-- Tela "Nova retirada": vários equipamentos do setor com a mesma OS e o mesmo prazo.
-- p_equipamentos = JSON com os códigos, ex.: '["NOTE-DEV-002","SRV-DEV-005"]'
-- O prazo vale até as 18:00 da data informada (padrão das telas).
CREATE PROCEDURE sp_emprestimo_solicitar(IN p_codigo_os VARCHAR(20), IN p_solicitante_id INT UNSIGNED,
                                         IN p_equipamentos JSON, IN p_prazo DATE, IN p_aceite TINYINT(1))
BEGIN
  DECLARE v_prazo DATETIME;
  DECLARE v_pedidos INT DEFAULT 0;
  DECLARE v_achados INT DEFAULT 0;
  DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;

  IF p_equipamentos IS NULL OR JSON_TYPE(p_equipamentos) <> 'ARRAY' OR JSON_LENGTH(p_equipamentos) = 0 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Selecione ao menos um equipamento.';
  END IF;
  IF TRIM(COALESCE(p_codigo_os,'')) = '' THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Informe o código do projeto ou da OS.';
  END IF;
  IF p_prazo IS NULL THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Informe o prazo previsto de devolução.';
  END IF;
  IF COALESCE(p_aceite,0) <> 1 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Aceite o termo digital para continuar.';
  END IF;
  IF NOT fn_usuario_tem_perfil(p_solicitante_id, 'GESTOR') THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Somente gestores podem solicitar retiradas.';
  END IF;
  SET v_prazo = TIMESTAMP(p_prazo, '18:00:00');
  IF v_prazo <= NOW() THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'O prazo de devolução deve ser uma data futura.';
  END IF;

  SELECT COUNT(DISTINCT UPPER(TRIM(jt.codigo))) INTO v_pedidos
    FROM JSON_TABLE(p_equipamentos, '$[*]' COLUMNS (codigo VARCHAR(20) PATH '$')) jt;
  SELECT COUNT(*) INTO v_achados
    FROM equipamentos q
    JOIN (SELECT DISTINCT UPPER(TRIM(jt.codigo)) AS codigo
            FROM JSON_TABLE(p_equipamentos, '$[*]' COLUMNS (codigo VARCHAR(20) PATH '$')) jt) x
      ON x.codigo = q.codigo_patrimonio;
  IF v_achados <> v_pedidos THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Há código de patrimônio inexistente na solicitação.';
  END IF;

  START TRANSACTION;
  -- o trigger trg_emprestimos_bi confere disponibilidade e setor de cada item
  INSERT INTO emprestimos (codigo_os, equipamento_id, setor_id, solicitante_id, aceite_termo, prazo_original, prazo_devolucao)
  SELECT UPPER(TRIM(p_codigo_os)), q.id, q.setor_id, p_solicitante_id, 1, v_prazo, v_prazo
    FROM equipamentos q
    JOIN (SELECT DISTINCT UPPER(TRIM(jt.codigo)) AS codigo
            FROM JSON_TABLE(p_equipamentos, '$[*]' COLUMNS (codigo VARCHAR(20) PATH '$')) jt) x
      ON x.codigo = q.codigo_patrimonio;
  COMMIT;

  SELECT * FROM vw_solicitacoes_pendentes WHERE codigo_os = UPPER(TRIM(p_codigo_os));
END$$

-- p_status: PENDENTE | ATIVO | DEVOLVIDO | RECUSADO | CANCELADO (NULL = todos)
CREATE PROCEDURE sp_emprestimo_listar(IN p_status VARCHAR(20), IN p_setor_id INT UNSIGNED, IN p_busca VARCHAR(100))
BEGIN
  SELECT e.id AS emprestimo_id, e.codigo_os, e.status, q.codigo_patrimonio, q.nome AS equipamento,
         s.nome_curto AS setor, u.nome AS solicitante, e.solicitado_em, e.retirado_em,
         e.prazo_original, e.prazo_devolucao, e.devolvido_em
    FROM emprestimos e
    JOIN equipamentos q ON q.id = e.equipamento_id
    JOIN setores s      ON s.id = e.setor_id
    JOIN usuarios u     ON u.id = e.solicitante_id
   WHERE (p_status IS NULL OR e.status = p_status)
     AND (p_setor_id IS NULL OR e.setor_id = p_setor_id)
     AND (p_busca IS NULL OR p_busca = '' OR CONCAT_WS(' ', e.codigo_os, q.codigo_patrimonio, q.nome) LIKE CONCAT('%', p_busca, '%'))
   ORDER BY e.solicitado_em DESC, e.id DESC;
END$$

CREATE PROCEDURE sp_emprestimo_obter(IN p_id INT UNSIGNED)
BEGIN
  SELECT e.*, q.codigo_patrimonio, q.nome AS equipamento, s.nome AS setor,
         u.nome AS solicitante, a.nome AS analisado_por_nome
    FROM emprestimos e
    JOIN equipamentos q ON q.id = e.equipamento_id
    JOIN setores s      ON s.id = e.setor_id
    JOIN usuarios u     ON u.id = e.solicitante_id
    LEFT JOIN usuarios a ON a.id = e.analisado_por
   WHERE e.id = p_id;
  SELECT * FROM extensoes_prazo WHERE emprestimo_id = p_id;
  SELECT d.*, u.nome AS recebido_por_nome FROM devolucoes d JOIN usuarios u ON u.id = d.recebido_por WHERE d.emprestimo_id = p_id;
END$$

-- Editar OS/prazo só enquanto a solicitação está PENDENTE
CREATE PROCEDURE sp_emprestimo_atualizar(IN p_id INT UNSIGNED, IN p_codigo_os VARCHAR(20), IN p_prazo DATE)
BEGIN
  DECLARE v_status VARCHAR(20);
  DECLARE v_prazo DATETIME;
  DECLARE EXIT HANDLER FOR 3819 SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Prazo inválido.';
  SELECT status INTO v_status FROM emprestimos WHERE id = p_id;
  IF v_status IS NULL THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Empréstimo não encontrado.'; END IF;
  IF v_status <> 'PENDENTE' THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Só é possível editar solicitações pendentes. Para mudar o prazo de um empréstimo ativo, use a extensão.';
  END IF;
  SET v_prazo = TIMESTAMP(p_prazo, '18:00:00');
  IF v_prazo <= NOW() THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'O prazo de devolução deve ser uma data futura.'; END IF;
  IF TRIM(COALESCE(p_codigo_os,'')) = '' THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Informe o código do projeto ou da OS.'; END IF;
  UPDATE emprestimos SET codigo_os = UPPER(TRIM(p_codigo_os)), prazo_original = v_prazo, prazo_devolucao = v_prazo WHERE id = p_id;
  CALL sp_emprestimo_obter(p_id);
END$$

-- Almoxarifado aprova: o item só vira EMPRESTADO aqui
CREATE PROCEDURE sp_emprestimo_aprovar(IN p_id INT UNSIGNED, IN p_almoxarife_id INT UNSIGNED)
BEGIN
  DECLARE v_status VARCHAR(20);
  DECLARE v_equip INT UNSIGNED;
  DECLARE v_status_equip VARCHAR(20);
  DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;
  IF NOT fn_usuario_tem_perfil(p_almoxarife_id, 'ALMOXARIFADO') THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Somente o Almoxarifado aprova retiradas.';
  END IF;
  START TRANSACTION;
  SELECT status, equipamento_id INTO v_status, v_equip FROM emprestimos WHERE id = p_id FOR UPDATE;
  IF v_status IS NULL THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Solicitação não encontrada.'; END IF;
  IF v_status <> 'PENDENTE' THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Esta solicitação não está pendente.'; END IF;
  SELECT status INTO v_status_equip FROM equipamentos WHERE id = v_equip FOR UPDATE;
  IF v_status_equip <> 'DISPONIVEL' THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Item indisponível: não é possível aprovar.'; END IF;
  UPDATE emprestimos SET status = 'ATIVO', analisado_por = p_almoxarife_id, analisado_em = NOW(), retirado_em = NOW()
   WHERE id = p_id;
  UPDATE equipamentos SET status = 'EMPRESTADO' WHERE id = v_equip;
  COMMIT;
  CALL sp_emprestimo_obter(p_id);
END$$

CREATE PROCEDURE sp_emprestimo_recusar(IN p_id INT UNSIGNED, IN p_almoxarife_id INT UNSIGNED, IN p_motivo VARCHAR(255))
BEGIN
  DECLARE v_status VARCHAR(20);
  IF NOT fn_usuario_tem_perfil(p_almoxarife_id, 'ALMOXARIFADO') THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Somente o Almoxarifado recusa retiradas.';
  END IF;
  IF TRIM(COALESCE(p_motivo,'')) = '' THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Informe o motivo da recusa.'; END IF;
  SELECT status INTO v_status FROM emprestimos WHERE id = p_id;
  IF v_status IS NULL THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Solicitação não encontrada.'; END IF;
  IF v_status <> 'PENDENTE' THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Esta solicitação não está pendente.'; END IF;
  UPDATE emprestimos SET status = 'RECUSADO', analisado_por = p_almoxarife_id, analisado_em = NOW(), motivo_recusa = TRIM(p_motivo)
   WHERE id = p_id;
  CALL sp_emprestimo_obter(p_id);
END$$

-- O próprio gestor desiste do pedido enquanto ele está pendente
CREATE PROCEDURE sp_emprestimo_cancelar(IN p_id INT UNSIGNED, IN p_solicitante_id INT UNSIGNED)
BEGIN
  DECLARE v_status VARCHAR(20);
  DECLARE v_dono INT UNSIGNED;
  SELECT status, solicitante_id INTO v_status, v_dono FROM emprestimos WHERE id = p_id;
  IF v_status IS NULL THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Solicitação não encontrada.'; END IF;
  IF v_status <> 'PENDENTE' THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Só é possível cancelar solicitações pendentes.'; END IF;
  IF v_dono <> p_solicitante_id THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Só quem fez o pedido pode cancelá-lo.'; END IF;
  UPDATE emprestimos SET status = 'CANCELADO' WHERE id = p_id;
  CALL sp_emprestimo_obter(p_id);
END$$

-- Apaga de vez apenas o que nunca virou empréstimo (pendente, recusado ou cancelado)
CREATE PROCEDURE sp_emprestimo_excluir(IN p_id INT UNSIGNED)
BEGIN
  DECLARE v_status VARCHAR(20);
  SELECT status INTO v_status FROM emprestimos WHERE id = p_id;
  IF v_status IS NULL THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Empréstimo não encontrado.'; END IF;
  IF v_status IN ('ATIVO','DEVOLVIDO') THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Exclusão bloqueada: empréstimos ativos ou devolvidos fazem parte do histórico.';
  END IF;
  DELETE FROM emprestimos WHERE id = p_id;
END$$

-- Tela "Registrar devolução" (só o Almoxarifado; devolução em mãos).
--   p_destino: DISPONIVEL | MANUTENCAO | DESCARTE
--   p_detalhe: insumo reposto (opcional) | defeito identificado (obrigatório) | motivo do descarte (obrigatório)
--   p_checklist: JSON com os ids dos itens conferidos, ex. '[1,2,3,4,5]'. NULL = todos conferidos.
CREATE PROCEDURE sp_emprestimo_registrar_devolucao(IN p_id INT UNSIGNED, IN p_almoxarife_id INT UNSIGNED,
                                                   IN p_destino VARCHAR(20), IN p_detalhe VARCHAR(255),
                                                   IN p_observacao VARCHAR(500), IN p_checklist JSON)
BEGIN
  DECLARE v_status VARCHAR(20);
  DECLARE v_equip INT UNSIGNED;
  DECLARE v_dev INT UNSIGNED;
  DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;

  IF NOT fn_usuario_tem_perfil(p_almoxarife_id, 'ALMOXARIFADO') THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Somente o Almoxarifado registra devoluções.';
  END IF;
  IF p_destino NOT IN ('DISPONIVEL','MANUTENCAO','DESCARTE') THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Destino na vistoria inválido.';
  END IF;
  IF p_destino = 'MANUTENCAO' AND TRIM(COALESCE(p_detalhe,'')) = '' THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Informe o defeito identificado.';
  END IF;
  IF p_destino = 'DESCARTE' AND TRIM(COALESCE(p_detalhe,'')) = '' THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Informe o motivo do descarte.';
  END IF;

  START TRANSACTION;
  SELECT status, equipamento_id INTO v_status, v_equip FROM emprestimos WHERE id = p_id FOR UPDATE;
  IF v_status IS NULL THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Empréstimo não encontrado.'; END IF;
  IF v_status <> 'ATIVO' THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Este empréstimo não está ativo.'; END IF;

  INSERT INTO devolucoes (emprestimo_id, recebido_por, destino, detalhe, observacao)
  VALUES (p_id, p_almoxarife_id, p_destino, NULLIF(TRIM(p_detalhe),''), NULLIF(TRIM(p_observacao),''));
  SET v_dev = LAST_INSERT_ID();

  INSERT INTO devolucao_checklist (devolucao_id, checklist_item_id, conferido)
  SELECT v_dev, c.id, IF(p_checklist IS NULL, 1, JSON_CONTAINS(p_checklist, CAST(c.id AS JSON)))
    FROM checklist_itens c WHERE c.ativo = 1;

  UPDATE emprestimos SET status = 'DEVOLVIDO', devolvido_em = NOW() WHERE id = p_id;

  IF p_destino = 'DISPONIVEL' THEN
    UPDATE equipamentos SET status = 'DISPONIVEL' WHERE id = v_equip;
  ELSEIF p_destino = 'MANUTENCAO' THEN
    UPDATE equipamentos SET status = 'MANUTENCAO' WHERE id = v_equip;
    INSERT INTO manutencoes (equipamento_id, devolucao_id, motivo) VALUES (v_equip, v_dev, TRIM(p_detalhe));
  ELSE
    UPDATE equipamentos SET status = 'DESCARTADO' WHERE id = v_equip;
    INSERT INTO alertas_compra (equipamento_id, devolucao_id, motivo) VALUES (v_equip, v_dev, TRIM(p_detalhe));
  END IF;
  COMMIT;

  SELECT v_dev AS devolucao_id, q.codigo_patrimonio, q.nome, q.status AS status_final
    FROM equipamentos q WHERE q.id = v_equip;
END$$

-- =====================================================================
-- EXTENSÕES DE PRAZO · gestor pede, Diretoria decide (1 por empréstimo)
-- =====================================================================
CREATE PROCEDURE sp_extensao_solicitar(IN p_emprestimo_id INT UNSIGNED, IN p_solicitante_id INT UNSIGNED,
                                       IN p_novo_prazo DATE, IN p_justificativa VARCHAR(500))
BEGIN
  DECLARE EXIT HANDLER FOR 1062 SIGNAL SQLSTATE '45000'
    SET MESSAGE_TEXT = 'Este empréstimo já teve um pedido de extensão. Só é permitida 1 por empréstimo.';
  DECLARE EXIT HANDLER FOR 3819 SIGNAL SQLSTATE '45000'
    SET MESSAGE_TEXT = 'A nova data deve ser posterior ao prazo atual e a justificativa é obrigatória.';
  IF TRIM(COALESCE(p_justificativa,'')) = '' THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Informe a justificativa formal.'; END IF;
  IF p_novo_prazo IS NULL THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Informe a nova data pretendida.'; END IF;
  -- prazo_atual é preenchido pelo trigger trg_extensoes_bi
  INSERT INTO extensoes_prazo (emprestimo_id, solicitante_id, prazo_atual, novo_prazo, justificativa)
  VALUES (p_emprestimo_id, p_solicitante_id, NOW(), TIMESTAMP(p_novo_prazo, '18:00:00'), TRIM(p_justificativa));
  CALL sp_extensao_obter(LAST_INSERT_ID());
END$$

-- p_status: PENDENTE | APROVADA | RECUSADA (NULL = todas); p_setor_id opcional
CREATE PROCEDURE sp_extensao_listar(IN p_status VARCHAR(20), IN p_setor_id INT UNSIGNED)
BEGIN
  SELECT x.id AS extensao_id, e.id AS emprestimo_id, e.codigo_os, q.codigo_patrimonio, q.nome AS equipamento,
         s.nome_curto AS setor, x.prazo_atual, x.novo_prazo, x.justificativa, x.status,
         u.nome AS solicitante, x.solicitado_em, d.nome AS decidido_por, x.decidido_em
    FROM extensoes_prazo x
    JOIN emprestimos e  ON e.id = x.emprestimo_id
    JOIN equipamentos q ON q.id = e.equipamento_id
    JOIN setores s      ON s.id = e.setor_id
    JOIN usuarios u     ON u.id = x.solicitante_id
    LEFT JOIN usuarios d ON d.id = x.decidido_por
   WHERE (p_status IS NULL OR x.status = p_status)
     AND (p_setor_id IS NULL OR e.setor_id = p_setor_id)
   ORDER BY x.solicitado_em DESC;
END$$

CREATE PROCEDURE sp_extensao_obter(IN p_id INT UNSIGNED)
BEGIN
  SELECT x.*, e.codigo_os, q.codigo_patrimonio, q.nome AS equipamento
    FROM extensoes_prazo x
    JOIN emprestimos e  ON e.id = x.emprestimo_id
    JOIN equipamentos q ON q.id = e.equipamento_id
   WHERE x.id = p_id;
END$$

CREATE PROCEDURE sp_extensao_atualizar(IN p_id INT UNSIGNED, IN p_novo_prazo DATE, IN p_justificativa VARCHAR(500))
BEGIN
  DECLARE v_status VARCHAR(20);
  DECLARE EXIT HANDLER FOR 3819 SIGNAL SQLSTATE '45000'
    SET MESSAGE_TEXT = 'A nova data deve ser posterior ao prazo atual e a justificativa é obrigatória.';
  SELECT status INTO v_status FROM extensoes_prazo WHERE id = p_id;
  IF v_status IS NULL THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Pedido de extensão não encontrado.'; END IF;
  IF v_status <> 'PENDENTE' THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Só é possível editar pedidos pendentes.'; END IF;
  UPDATE extensoes_prazo SET novo_prazo = TIMESTAMP(p_novo_prazo, '18:00:00'), justificativa = TRIM(p_justificativa) WHERE id = p_id;
  CALL sp_extensao_obter(p_id);
END$$

-- Aprovar muda o prazo do empréstimo; recusar mantém o prazo (e a extensão conta como utilizada)
CREATE PROCEDURE sp_extensao_decidir(IN p_id INT UNSIGNED, IN p_diretor_id INT UNSIGNED, IN p_aprovar TINYINT(1))
BEGIN
  DECLARE v_status VARCHAR(20);
  DECLARE v_emp INT UNSIGNED;
  DECLARE v_novo DATETIME;
  DECLARE v_status_emp VARCHAR(20);
  DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;
  IF NOT fn_usuario_tem_perfil(p_diretor_id, 'DIRETORIA') THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Somente a Diretoria decide extensões de prazo.';
  END IF;
  START TRANSACTION;
  SELECT status, emprestimo_id, novo_prazo INTO v_status, v_emp, v_novo FROM extensoes_prazo WHERE id = p_id FOR UPDATE;
  IF v_status IS NULL THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Pedido de extensão não encontrado.'; END IF;
  IF v_status <> 'PENDENTE' THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Este pedido já foi decidido.'; END IF;
  SELECT status INTO v_status_emp FROM emprestimos WHERE id = v_emp FOR UPDATE;
  IF v_status_emp <> 'ATIVO' THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'O empréstimo já foi encerrado.'; END IF;

  UPDATE extensoes_prazo
     SET status = IF(p_aprovar = 1, 'APROVADA', 'RECUSADA'), decidido_por = p_diretor_id, decidido_em = NOW()
   WHERE id = p_id;
  IF p_aprovar = 1 THEN
    UPDATE emprestimos SET prazo_devolucao = v_novo WHERE id = v_emp;
  END IF;
  COMMIT;
  CALL sp_extensao_obter(p_id);
END$$

-- Retirar o pedido pendente (o empréstimo volta a poder pedir)
CREATE PROCEDURE sp_extensao_excluir(IN p_id INT UNSIGNED)
BEGIN
  DECLARE v_status VARCHAR(20);
  SELECT status INTO v_status FROM extensoes_prazo WHERE id = p_id;
  IF v_status IS NULL THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Pedido de extensão não encontrado.'; END IF;
  IF v_status <> 'PENDENTE' THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Exclusão bloqueada: pedidos já decididos ficam no histórico.'; END IF;
  DELETE FROM extensoes_prazo WHERE id = p_id;
END$$

-- =====================================================================
-- MANUTENÇÃO · vistoria envia -> oficina repara -> almoxarifado valida -> Disponível
-- (a maioria das manutenções nasce na devolução; sp_manutencao_abrir cobre o envio direto)
-- =====================================================================
CREATE PROCEDURE sp_manutencao_abrir(IN p_equipamento_id INT UNSIGNED, IN p_motivo VARCHAR(255), IN p_almoxarife_id INT UNSIGNED)
BEGIN
  DECLARE v_status VARCHAR(20);
  DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;
  IF NOT fn_usuario_tem_perfil(p_almoxarife_id, 'ALMOXARIFADO') THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Somente o Almoxarifado envia equipamentos para manutenção.';
  END IF;
  IF TRIM(COALESCE(p_motivo,'')) = '' THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Informe o defeito identificado.'; END IF;
  START TRANSACTION;
  SELECT status INTO v_status FROM equipamentos WHERE id = p_equipamento_id FOR UPDATE;
  IF v_status IS NULL THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Equipamento não encontrado.'; END IF;
  IF v_status <> 'DISPONIVEL' THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Só equipamentos disponíveis podem ser enviados direto para manutenção.'; END IF;
  UPDATE equipamentos SET status = 'MANUTENCAO' WHERE id = p_equipamento_id;
  INSERT INTO manutencoes (equipamento_id, motivo) VALUES (p_equipamento_id, TRIM(p_motivo));
  COMMIT;
  CALL sp_manutencao_obter(LAST_INSERT_ID());
END$$

-- p_etapa: EM_REPARO | REPARO_CONCLUIDO | VALIDADA (NULL = só as abertas, ou seja, não validadas)
CREATE PROCEDURE sp_manutencao_listar(IN p_etapa VARCHAR(20))
BEGIN
  SELECT * FROM vw_manutencoes
   WHERE (p_etapa IS NULL AND etapa <> 'VALIDADA') OR etapa = p_etapa
   ORDER BY enviado_em;
END$$

CREATE PROCEDURE sp_manutencao_obter(IN p_id INT UNSIGNED)
BEGIN
  SELECT * FROM vw_manutencoes WHERE manutencao_id = p_id;
END$$

CREATE PROCEDURE sp_manutencao_atualizar(IN p_id INT UNSIGNED, IN p_motivo VARCHAR(255))
BEGIN
  DECLARE v_etapa VARCHAR(20);
  SELECT etapa INTO v_etapa FROM manutencoes WHERE id = p_id;
  IF v_etapa IS NULL THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Manutenção não encontrada.'; END IF;
  IF v_etapa = 'VALIDADA' THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Manutenção já validada não pode ser editada.'; END IF;
  IF TRIM(COALESCE(p_motivo,'')) = '' THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Informe o motivo.'; END IF;
  UPDATE manutencoes SET motivo = TRIM(p_motivo) WHERE id = p_id;
  CALL sp_manutencao_obter(p_id);
END$$

-- Oficina: só o gestor do setor Manutenção e Suporte (sigla ms)
CREATE PROCEDURE sp_manutencao_concluir(IN p_id INT UNSIGNED, IN p_gestor_id INT UNSIGNED, IN p_observacao VARCHAR(500))
BEGIN
  DECLARE v_etapa VARCHAR(20);
  IF NOT EXISTS (SELECT 1 FROM usuarios u JOIN setores s ON s.id = u.setor_id
                  WHERE u.id = p_gestor_id AND u.perfil = 'GESTOR' AND u.ativo = 1 AND s.sigla = 'ms') THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Somente o gestor de Manutenção e Suporte conclui reparos.';
  END IF;
  SELECT etapa INTO v_etapa FROM manutencoes WHERE id = p_id;
  IF v_etapa IS NULL THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Manutenção não encontrada.'; END IF;
  IF v_etapa <> 'EM_REPARO' THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Este reparo não está em andamento.'; END IF;
  UPDATE manutencoes SET etapa = 'REPARO_CONCLUIDO', concluido_por = p_gestor_id, concluido_em = NOW(),
                         observacao_reparo = NULLIF(TRIM(p_observacao),'')
   WHERE id = p_id;
  CALL sp_manutencao_obter(p_id);
END$$

-- Almoxarifado valida o recebimento: o item volta a Disponível
CREATE PROCEDURE sp_manutencao_validar(IN p_id INT UNSIGNED, IN p_almoxarife_id INT UNSIGNED)
BEGIN
  DECLARE v_etapa VARCHAR(20);
  DECLARE v_equip INT UNSIGNED;
  DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;
  IF NOT fn_usuario_tem_perfil(p_almoxarife_id, 'ALMOXARIFADO') THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Somente o Almoxarifado valida o recebimento.';
  END IF;
  START TRANSACTION;
  SELECT etapa, equipamento_id INTO v_etapa, v_equip FROM manutencoes WHERE id = p_id FOR UPDATE;
  IF v_etapa IS NULL THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Manutenção não encontrada.'; END IF;
  IF v_etapa <> 'REPARO_CONCLUIDO' THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'O reparo ainda não foi concluído pela oficina.'; END IF;
  UPDATE manutencoes SET etapa = 'VALIDADA', validado_por = p_almoxarife_id, validado_em = NOW() WHERE id = p_id;
  UPDATE equipamentos SET status = 'DISPONIVEL' WHERE id = v_equip;
  COMMIT;
  CALL sp_manutencao_obter(p_id);
END$$

-- Cancela um registro aberto por engano (só EM_REPARO); o item volta a Disponível
CREATE PROCEDURE sp_manutencao_excluir(IN p_id INT UNSIGNED)
BEGIN
  DECLARE v_etapa VARCHAR(20);
  DECLARE v_equip INT UNSIGNED;
  DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;
  START TRANSACTION;
  SELECT etapa, equipamento_id INTO v_etapa, v_equip FROM manutencoes WHERE id = p_id FOR UPDATE;
  IF v_etapa IS NULL THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Manutenção não encontrada.'; END IF;
  IF v_etapa <> 'EM_REPARO' THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Exclusão bloqueada: só é possível excluir reparos ainda em andamento.'; END IF;
  DELETE FROM manutencoes WHERE id = p_id;
  UPDATE equipamentos SET status = 'DISPONIVEL' WHERE id = v_equip;
  COMMIT;
END$$

-- =====================================================================
-- ALERTAS DE COMPRA · nascem do descarte; a Diretoria autoriza
-- =====================================================================
CREATE PROCEDURE sp_compra_registrar(IN p_equipamento_id INT UNSIGNED, IN p_motivo VARCHAR(255))
BEGIN
  DECLARE EXIT HANDLER FOR 1062 SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Já existe alerta de compra para este equipamento.';
  IF NOT EXISTS (SELECT 1 FROM equipamentos WHERE id = p_equipamento_id AND status = 'DESCARTADO') THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Só equipamentos descartados geram alerta de compra.';
  END IF;
  IF TRIM(COALESCE(p_motivo,'')) = '' THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Informe o motivo.'; END IF;
  INSERT INTO alertas_compra (equipamento_id, motivo) VALUES (p_equipamento_id, TRIM(p_motivo));
  CALL sp_compra_obter(LAST_INSERT_ID());
END$$

CREATE PROCEDURE sp_compra_listar(IN p_status VARCHAR(20))
BEGIN
  SELECT * FROM vw_alertas_compra WHERE p_status IS NULL OR status = p_status ORDER BY criado_em;
END$$

CREATE PROCEDURE sp_compra_obter(IN p_id INT UNSIGNED)
BEGIN
  SELECT * FROM vw_alertas_compra WHERE alerta_id = p_id;
END$$

CREATE PROCEDURE sp_compra_atualizar(IN p_id INT UNSIGNED, IN p_motivo VARCHAR(255))
BEGIN
  DECLARE v_status VARCHAR(20);
  SELECT status INTO v_status FROM alertas_compra WHERE id = p_id;
  IF v_status IS NULL THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Alerta de compra não encontrado.'; END IF;
  IF v_status <> 'PENDENTE' THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Só é possível editar alertas pendentes.'; END IF;
  IF TRIM(COALESCE(p_motivo,'')) = '' THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Informe o motivo.'; END IF;
  UPDATE alertas_compra SET motivo = TRIM(p_motivo) WHERE id = p_id;
  CALL sp_compra_obter(p_id);
END$$

CREATE PROCEDURE sp_compra_autorizar(IN p_id INT UNSIGNED, IN p_diretor_id INT UNSIGNED)
BEGIN
  DECLARE v_status VARCHAR(20);
  IF NOT fn_usuario_tem_perfil(p_diretor_id, 'DIRETORIA') THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Somente a Diretoria autoriza compras.';
  END IF;
  SELECT status INTO v_status FROM alertas_compra WHERE id = p_id;
  IF v_status IS NULL THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Alerta de compra não encontrado.'; END IF;
  IF v_status <> 'PENDENTE' THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Esta compra já foi autorizada.'; END IF;
  UPDATE alertas_compra SET status = 'AUTORIZADA', autorizado_por = p_diretor_id, autorizado_em = NOW() WHERE id = p_id;
  CALL sp_compra_obter(p_id);
END$$

CREATE PROCEDURE sp_compra_excluir(IN p_id INT UNSIGNED)
BEGIN
  DECLARE v_status VARCHAR(20);
  SELECT status INTO v_status FROM alertas_compra WHERE id = p_id;
  IF v_status IS NULL THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Alerta de compra não encontrado.'; END IF;
  IF v_status <> 'PENDENTE' THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Exclusão bloqueada: compras autorizadas ficam registradas.'; END IF;
  DELETE FROM alertas_compra WHERE id = p_id;
END$$

-- =====================================================================
-- HISTÓRICO (tela Histórico de movimentações; gestor passa o próprio setor)
-- =====================================================================
CREATE PROCEDURE sp_historico_listar(IN p_setor_id INT UNSIGNED, IN p_busca VARCHAR(100))
BEGIN
  SELECT * FROM vw_historico
   WHERE (p_setor_id IS NULL OR setor_id = p_setor_id)
     AND (p_busca IS NULL OR p_busca = '' OR CONCAT_WS(' ', codigo_patrimonio, equipamento, codigo_os) LIKE CONCAT('%', p_busca, '%'))
   ORDER BY COALESCE(devolvido_em, retirado_em) DESC;
END$$

DELIMITER ;
-- =====================================================================
-- TechRental · 04 · Dados iniciais (os mesmos dados fictícios do protótipo)
-- Senha de todos os usuários de teste: 12345678  (hashes copiados do login.php)
-- =====================================================================
USE techrental;
SET NAMES utf8mb4;

INSERT INTO setores (sigla, nome, nome_curto) VALUES
  ('dev', 'Desenvolvimento de Software',        'Software'),
  ('pd',  'Engenharia e Prototipagem (P&D)',    'P&D'),
  ('cp',  'Implantação e Operações em Campo',   'Campo'),
  ('ms',  'Manutenção e Suporte Técnico',       'Suporte');

INSERT INTO categorias (nome) VALUES
  ('Notebooks'), ('Kits Eletrônicos'), ('Ferramentas'), ('Equipamentos Tecnológicos');

INSERT INTO checklist_itens (descricao, ordem) VALUES
  ('Equipamento principal', 1), ('Carregador / fonte', 2), ('Cabos fornecidos', 3),
  ('Acessórios da retirada', 4), ('Sem avarias físicas visíveis', 5);

INSERT INTO usuarios (nome, email, senha_hash, perfil, setor_id) VALUES
  ('Almoxarife', 'almoxarifado@techrental.com', '$2y$10$NrTtS2ZxdG/DUOEHvty8ae5NH431Jldc190I6/wBSeWNVEZ8cg9SK', 'ALMOXARIFADO', NULL),
  ('Gestor Software', 'gestor.software@techrental.com', '$2y$10$BEDr8F6iDFU/FkenNFk7NOlQt1p2vYTt5F4hCUqIRd0tgKK0rYS6u', 'GESTOR', fn_setor_id('dev')),
  ('Gestor P&D', 'gestor.pd@techrental.com', '$2y$10$V/jGXRDB0YH0u9ooAZGFd.Vi/mqy..SDp4cRoTaK02n.diMPVhRrS', 'GESTOR', fn_setor_id('pd')),
  ('Gestor Campo', 'gestor.campo@techrental.com', '$2y$10$YpQ/mqX575MTB0Ipjres9Oe9EjI1ppUJ.B.SBdSdEqKm.hG6zun4C', 'GESTOR', fn_setor_id('cp')),
  ('Gestor Suporte', 'gestor.suporte@techrental.com', '$2y$10$KuUL5zguB0fKu0PpHI7dPO0chXvXQy2/yZ.m3Q0v0gcnSJX6Qer22', 'GESTOR', fn_setor_id('ms')),
  ('Diretor', 'diretoria@techrental.com', '$2y$10$0fee8qPcWmY4Mg6GkF/B4eU4dXbaAvdWdk7UJHEFHSSL/HNeH992y', 'DIRETORIA', NULL);

-- 24 equipamentos (a coluna status já reflete o estado atual; os empréstimos abaixo são coerentes com ele)
INSERT INTO equipamentos (codigo_patrimonio, nome, categoria_id, setor_id, status, condicao_inicial, uso_principal) VALUES
  ('NOTE-DEV-001', 'Notebook Workstation de Alta Performance', 1, fn_setor_id('dev'), 'EMPRESTADO', 'INTEGRO', 'Compilação pesada e máquinas virtuais.'),
  ('NOTE-DEV-002', 'Notebook Padrão de Homologação', 1, fn_setor_id('dev'), 'DISPONIVEL', 'INTEGRO', 'Testes em configurações comuns de cliente.'),
  ('TAB-DEV-003', 'Tablet Industrial', 4, fn_setor_id('dev'), 'EMPRESTADO', 'INTEGRO', 'Valida interfaces de apps de controle em campo.'),
  ('PHN-DEV-004', 'Smartphone de Testes', 4, fn_setor_id('dev'), 'EMPRESTADO', 'INTEGRO', 'Homologação de apps móveis de automação.'),
  ('SRV-DEV-005', 'Servidor Portátil (Mini PC)', 4, fn_setor_id('dev'), 'DISPONIVEL', 'INTEGRO', 'Simula redes locais durante o desenvolvimento.'),
  ('KIT-DEV-006', 'Kit de Conectividade (Hubs e Adaptadores)', 2, fn_setor_id('dev'), 'DISPONIVEL', 'INTEGRO', 'Integra notebooks e periféricos de teste.'),
  ('KIT-PD-001', 'Kit Microcontrolador Avançado (ESP32 / Arduino)', 2, fn_setor_id('pd'), 'EMPRESTADO', 'INTEGRO', 'Base para programar e testar dispositivos.'),
  ('SENS-PD-002', 'Kit de Sensores Industriais', 2, fn_setor_id('pd'), 'DISPONIVEL', 'INTEGRO', 'Temperatura, umidade, presença e movimento.'),
  ('SOLD-PD-003', 'Estação de Solda Digital', 3, fn_setor_id('pd'), 'DISPONIVEL', 'INTEGRO', 'Montagem e ajuste fino de placas.'),
  ('MULT-PD-004', 'Multímetro Digital de Bancada', 3, fn_setor_id('pd'), 'DISPONIVEL', 'INTEGRO', 'Mede tensão, corrente e continuidade.'),
  ('FONT-PD-005', 'Fonte de Alimentação Assimétrica', 4, fn_setor_id('pd'), 'DESCARTADO', 'INTEGRO', 'Alimenta protótipos com voltagens controladas.'),
  ('NOTE-PD-006', 'Notebook de Engenharia CAD', 1, fn_setor_id('pd'), 'EMPRESTADO', 'INTEGRO', 'Esquemas elétricos e firmwares.'),
  ('NOTE-CP-001', 'Notebook Robusto de Campo', 1, fn_setor_id('cp'), 'EMPRESTADO', 'INTEGRO', 'Configura roteadores, servidores e câmeras no cliente.'),
  ('PARA-CP-002', 'Parafusadeira e Furadeira de Impacto', 3, fn_setor_id('cp'), 'EMPRESTADO', 'INTEGRO', 'Fixação de racks, suportes e sensores.'),
  ('CRIMP-CP-003', 'Kit de Crimpagem e Cabeamento', 2, fn_setor_id('cp'), 'EMPRESTADO', 'INTEGRO', 'Alicate crimpador, decapador e testador de cabos.'),
  ('ROT-CP-004', 'Roteador Industrial 4G/5G', 4, fn_setor_id('cp'), 'DISPONIVEL', 'INTEGRO', 'Internet temporária durante a implantação.'),
  ('CAM-CP-005', 'Câmera IP de Homologação', 4, fn_setor_id('cp'), 'DISPONIVEL', 'INTEGRO', 'Testa posicionamento e monitoramento no cliente.'),
  ('ESC-CP-006', 'Escada Articulada Multifuncional', 3, fn_setor_id('cp'), 'DISPONIVEL', 'INTEGRO', 'Acesso a tetos e paredes altas.'),
  ('KIT-MS-001', 'Kit de Ferramentas de Precisão', 3, fn_setor_id('ms'), 'DISPONIVEL', 'INTEGRO', 'Chaves magnéticas e espátulas para equipamentos delicados.'),
  ('ALIC-MS-002', 'Multímetro Alicate Amperímetro', 3, fn_setor_id('ms'), 'EMPRESTADO', 'INTEGRO', 'Diagnostica falhas elétricas sem desligar o circuito.'),
  ('NOTE-MS-003', 'Notebook de Diagnóstico', 1, fn_setor_id('ms'), 'MANUTENCAO', 'INTEGRO', 'Softwares para leitura de erros e logs.'),
  ('COMP-MS-004', 'Kit de Componentes de Reposição', 2, fn_setor_id('ms'), 'DISPONIVEL', 'INTEGRO', 'Relés, fusíveis, fontes e conectores.'),
  ('ANAL-MS-005', 'Analisador de Rede Portátil', 4, fn_setor_id('ms'), 'MANUTENCAO', 'INTEGRO', 'Identifica falhas de sinal e perda de pacotes.'),
  ('TERM-MS-006', 'Câmera Termográfica Portátil', 4, fn_setor_id('ms'), 'DISPONIVEL', 'INTEGRO', 'Detecta superaquecimento em painéis e servidores.');

-- ---------------------------------------------------------------------
-- Empréstimos ATIVOS (9). Ano 2026. Prazos às 18:00. Atraso é calculado pela view.
-- ---------------------------------------------------------------------
INSERT INTO emprestimos (codigo_os, equipamento_id, setor_id, solicitante_id, status, aceite_termo,
                         solicitado_em, retirado_em, prazo_original, prazo_devolucao, analisado_por, analisado_em)
SELECT t.os, q.id, q.setor_id, fn_usuario_id(t.gestor), 'ATIVO', 1,
       t.retirada, t.retirada, t.prazo, t.prazo, fn_usuario_id('almoxarifado@techrental.com'), t.retirada
  FROM (
    SELECT 'NOTE-DEV-001' AS cod, 'OS-2026-0412' AS os, 'gestor.software@techrental.com' AS gestor, '2026-11-05 09:30:00' AS retirada, '2026-11-12 18:00:00' AS prazo UNION ALL
    SELECT 'TAB-DEV-003',  'OS-2026-0398', 'gestor.software@techrental.com', '2026-11-02 14:00:00', '2026-11-09 18:00:00' UNION ALL
    SELECT 'PHN-DEV-004',  'OS-2026-0377', 'gestor.software@techrental.com', '2026-10-28 10:15:00', '2026-11-06 18:00:00' UNION ALL
    SELECT 'KIT-PD-001',   'OS-2026-0420', 'gestor.pd@techrental.com',       '2026-11-06 08:50:00', '2026-11-14 18:00:00' UNION ALL
    SELECT 'NOTE-PD-006',  'OS-2026-0415', 'gestor.pd@techrental.com',       '2026-11-04 11:20:00', '2026-11-10 18:00:00' UNION ALL
    SELECT 'NOTE-CP-001',  'OS-2026-0390', 'gestor.campo@techrental.com',    '2026-11-03 13:40:00', '2026-11-11 18:00:00' UNION ALL
    SELECT 'PARA-CP-002',  'OS-2026-0388', 'gestor.campo@techrental.com',    '2026-10-29 09:10:00', '2026-11-08 18:00:00' UNION ALL
    SELECT 'CRIMP-CP-003', 'OS-2026-0402', 'gestor.campo@techrental.com',    '2026-10-30 15:00:00', '2026-11-10 18:00:00' UNION ALL
    SELECT 'ALIC-MS-002',  'OS-2026-0433', 'gestor.suporte@techrental.com',  '2026-11-06 10:05:00', '2026-11-12 18:00:00'
  ) t
  JOIN equipamentos q ON q.codigo_patrimonio = t.cod;

-- ---------------------------------------------------------------------
-- Solicitações PENDENTES (3)
-- ---------------------------------------------------------------------
INSERT INTO emprestimos (codigo_os, equipamento_id, solicitante_id, status, aceite_termo, solicitado_em, prazo_original, prazo_devolucao, setor_id)
SELECT t.os, q.id, fn_usuario_id(t.gestor), 'PENDENTE', 1, t.solicitado, t.prazo, t.prazo, q.setor_id
  FROM (
    SELECT 'SOLD-PD-003' AS cod, 'OS-2026-0431' AS os, 'gestor.pd@techrental.com'      AS gestor, '2026-11-09 08:40:00' AS solicitado, '2026-11-16 18:00:00' AS prazo UNION ALL
    SELECT 'ROT-CP-004',  'OS-2026-0428', 'gestor.campo@techrental.com',   '2026-11-08 16:10:00', '2026-11-15 18:00:00' UNION ALL
    SELECT 'TERM-MS-006', 'OS-2026-0425', 'gestor.suporte@techrental.com', '2026-11-08 11:25:00', '2026-11-14 18:00:00'
  ) t
  JOIN equipamentos q ON q.codigo_patrimonio = t.cod;

-- ---------------------------------------------------------------------
-- Extensões de prazo: 1 aprovada (NOTE-PD-006, já "utilizada") e 2 pendentes
-- ---------------------------------------------------------------------
INSERT INTO extensoes_prazo (emprestimo_id, solicitante_id, prazo_atual, novo_prazo, justificativa, status, solicitado_em, decidido_por, decidido_em)
SELECT e.id, fn_usuario_id('gestor.pd@techrental.com'), e.prazo_devolucao, '2026-11-13 18:00:00',
       'Validação do protótipo depende de mais uma rodada de testes.', 'APROVADA', '2026-11-06 09:00:00',
       fn_usuario_id('diretoria@techrental.com'), '2026-11-06 14:30:00'
  FROM emprestimos e WHERE e.codigo_os = 'OS-2026-0415';
UPDATE emprestimos SET prazo_devolucao = '2026-11-13 18:00:00' WHERE codigo_os = 'OS-2026-0415';

INSERT INTO extensoes_prazo (emprestimo_id, solicitante_id, prazo_atual, novo_prazo, justificativa, solicitado_em)
SELECT e.id, fn_usuario_id('gestor.software@techrental.com'), NOW(), '2026-11-16 18:00:00',
       'Homologação do app depende de novo lote de testes.', '2026-11-06 15:00:00'
  FROM emprestimos e WHERE e.codigo_os = 'OS-2026-0377';
INSERT INTO extensoes_prazo (emprestimo_id, solicitante_id, prazo_atual, novo_prazo, justificativa, solicitado_em)
SELECT e.id, fn_usuario_id('gestor.campo@techrental.com'), NOW(), '2026-11-14 18:00:00',
       'Cliente adiou a janela de implantação.', '2026-11-09 10:00:00'
  FROM emprestimos e WHERE e.codigo_os = 'OS-2026-0402';

-- ---------------------------------------------------------------------
-- Histórico: 4 empréstimos já DEVOLVIDOS, com vistoria
-- ---------------------------------------------------------------------
INSERT INTO emprestimos (codigo_os, equipamento_id, setor_id, solicitante_id, status, aceite_termo,
                         solicitado_em, retirado_em, prazo_original, prazo_devolucao, devolvido_em, analisado_por, analisado_em)
SELECT t.os, q.id, q.setor_id, fn_usuario_id(t.gestor), 'DEVOLVIDO', 1,
       t.retirada, t.retirada, t.prazo, t.prazo, t.devolucao, fn_usuario_id('almoxarifado@techrental.com'), t.retirada
  FROM (
    SELECT 'NOTE-DEV-002' AS cod, 'OS-2026-0344' AS os, 'gestor.software@techrental.com' AS gestor, '2026-10-12 09:00:00' AS retirada, '2026-10-20 18:00:00' AS prazo, '2026-10-19 16:20:00' AS devolucao UNION ALL
    SELECT 'SRV-DEV-005',  'OS-2026-0338', 'gestor.software@techrental.com', '2026-10-05 14:30:00', '2026-10-10 18:00:00', '2026-10-09 10:05:00' UNION ALL
    SELECT 'NOTE-MS-003',  'OS-2026-0371', 'gestor.suporte@techrental.com',  '2026-10-27 09:00:00', '2026-11-04 18:00:00', '2026-11-03 16:20:00' UNION ALL
    SELECT 'FONT-PD-005',  'OS-2026-0366', 'gestor.pd@techrental.com',       '2026-10-27 09:00:00', '2026-11-08 18:00:00', '2026-11-07 11:00:00'
  ) t
  JOIN equipamentos q ON q.codigo_patrimonio = t.cod;

INSERT INTO devolucoes (emprestimo_id, recebido_por, devolvido_em, destino, detalhe, observacao)
SELECT e.id, fn_usuario_id('almoxarifado@techrental.com'), e.devolvido_em, t.destino, t.detalhe, t.obs
  FROM (
    SELECT 'OS-2026-0344' AS os, 'DISPONIVEL' AS destino, NULL AS detalhe, 'Conferido, sem avarias.' AS obs UNION ALL
    SELECT 'OS-2026-0338', 'DISPONIVEL', 'Cabo de alimentação reposto', 'Faltou acessório básico. Reposto pelo Almoxarifado.' UNION ALL
    SELECT 'OS-2026-0371', 'MANUTENCAO', 'Falha na placa de vídeo', 'Falha técnica. Enviado à oficina de Manutenção.' UNION ALL
    SELECT 'OS-2026-0366', 'DESCARTE',   'Perda total após curto-circuito.', 'Perda total. Item descartado.'
  ) t
  JOIN emprestimos e ON e.codigo_os = t.os AND e.status = 'DEVOLVIDO';

INSERT INTO devolucao_checklist (devolucao_id, checklist_item_id, conferido)
SELECT d.id, c.id, 1 FROM devolucoes d CROSS JOIN checklist_itens c;

-- ---------------------------------------------------------------------
-- Manutenção: NOTE-MS-003 (reparo concluído, falta validar) e ANAL-MS-005 (na oficina)
-- ---------------------------------------------------------------------
INSERT INTO manutencoes (equipamento_id, devolucao_id, motivo, etapa, enviado_em, observacao_reparo, concluido_por, concluido_em)
SELECT fn_equipamento_id('NOTE-MS-003'), d.id, 'Falha na placa de vídeo', 'REPARO_CONCLUIDO', '2026-11-03 16:30:00',
       'Placa de vídeo substituída e testada.', fn_usuario_id('gestor.suporte@techrental.com'), '2026-11-09 09:00:00'
  FROM devolucoes d JOIN emprestimos e ON e.id = d.emprestimo_id WHERE e.codigo_os = 'OS-2026-0371';

INSERT INTO manutencoes (equipamento_id, motivo, etapa, enviado_em)
VALUES (fn_equipamento_id('ANAL-MS-005'), 'Porta Ethernet danificada', 'EM_REPARO', '2026-11-06 10:00:00');

-- ---------------------------------------------------------------------
-- Alerta de compra gerado pelo descarte da FONT-PD-005
-- ---------------------------------------------------------------------
INSERT INTO alertas_compra (equipamento_id, devolucao_id, motivo, criado_em)
SELECT fn_equipamento_id('FONT-PD-005'), d.id, 'Perda total após curto-circuito.', '2026-11-07 11:00:00'
  FROM devolucoes d JOIN emprestimos e ON e.id = d.emprestimo_id WHERE e.codigo_os = 'OS-2026-0366';
=======
CREATE TABLE IF NOT EXISTS exemplos (
    id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    titulo VARCHAR(120) NOT NULL,
    criado_em TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

>>>>>>> 12ff266662b0909ae355f6be7034df0bfac9ac72
