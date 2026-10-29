"""Asynchronous package transaction service for Redshift Store.

Manages package installation, removal, and system upgrades using QProcess with
real-time log streaming, multi-stage state tracking, safe cancellation (without SIGKILL),
interactive prompt detection, pacman db.lck enforcement, and graphical Polkit agent
guarantees. Supports deterministic mock simulations when REDSHIFT_STORE_MOCK=1.
"""

from __future__ import annotations

import logging
import os
import re
from typing import Sequence

from PyQt6.QtCore import (
    QObject,
    QProcess,
    QProcessEnvironment,
    QTimer,
    pyqtProperty,
    pyqtSignal,
    pyqtSlot,
)

from .catalog_service import is_mock_mode
from .security import (
    SecurityViolationError,
    build_safe_pacman_install_cmd,
    build_safe_pacman_remove_cmd,
    build_safe_pacman_sysupgrade_cmd,
    build_safe_yay_install_cmd,
    build_safe_yay_sysupgrade_cmd,
    ensure_polkit_agent,
    is_pacman_locked,
)

logger = logging.getLogger("redshift_store.transaction")

# Regex to detect pacman/yay progress percentage in stdout/stderr
PROGRESS_RE = re.compile(
    r"\((\d{1,3})%\)|(?:downloading|installing|upgrading|checking|baixando|instalando)\D+(\d{1,3})%",
    re.IGNORECASE,
)

# Regex to detect interactive prompts requiring user confirmation
PROMPT_RE = re.compile(
    r"(\[[Yy]/[Nn]\]|\[[Ss]/[Nn]\]|\[[Yy][Ee][Ss]/[Nn][Oo]\]|"
    r"Proceed with (?:install|installation|upgrade|removal)\?|Continuar a (?:instalação|atualização|remoção)\?|"
    r"Packages to cleanBuild\?|Pacotes para construir|"
    r"Diffs to show\?|Diffs para mostrar\?|"
    r"PKGBUILDs to edit\?|PKGBUILDs para editar\?|"
    r"\[N\]one\s+\[A\]ll\s+\[Ab\]ort|"
    r"Enter a number|Digite um número|Enter a selection|"
    r"Remove \w+\?|Remover \w+\?|Substituir \w+\?|::\s*Proceed|::\s*Continuar)",
    re.IGNORECASE,
)

# Stages where cancellation is safe without corrupting the pacman database
SAFE_CANCEL_STAGES: frozenset[str] = frozenset({
    "checking_updates",
    "authenticating",
    "downloading",
    "compiling",
})


class TransactionService(QObject):
    """Executes package manager transactions asynchronously without blocking the UI."""

    stateChanged = pyqtSignal(str, str)  # (state, status_text)
    progressChanged = pyqtSignal(int)  # 0..100 or -1 (indeterminate)
    logLineReceived = pyqtSignal(str)  # single log line
    transactionFinished = pyqtSignal(bool, str, str)  # (success, action, message)
    lockStatusChanged = pyqtSignal(bool)  # is_locked
    stageChanged = pyqtSignal()  # emitted when self._stage changes
    promptChanged = pyqtSignal()  # emitted when self._waiting_for_input or prompt text changes
    cancellationBlocked = pyqtSignal(str)  # emitted when cancel is attempted in unsafe stage
    lastOutcomeChanged = pyqtSignal(str, str)  # (outcome, summary)

    def __init__(self, parent: QObject | None = None, mock_mode: bool | None = None) -> None:
        super().__init__(parent)
        self.mock_mode = is_mock_mode() if mock_mode is None else mock_mode
        self._state: str = "idle"
        self._status_text: str = ""
        self._stage: str = "idle"
        self._progress: int = 0
        self._is_busy: bool = False
        self._current_action: str = ""
        self._current_packages: list[str] = []
        self._process: QProcess | None = None
        self._stdout_buffer: str = ""
        self._waiting_for_input: bool = False
        self._current_prompt_text: str = ""
        self._mock_timer: QTimer | None = None
        self._mock_step: int = 0
        self._mock_target_cmd: list[str] = []
        self._last_locked: bool | None = None
        self._recent_lines: list[str] = []
        self._last_outcome: str = ""
        self._last_summary: str = ""

    # -------------------------------------------------------------------------
    # Properties
    # -------------------------------------------------------------------------

    @property
    def last_outcome(self) -> str:
        """Return post-verification outcome ('complete'|'partial'|'cancelled'|'failed'|'')."""
        return self._last_outcome

    @property
    def last_summary(self) -> str:
        """Return human-readable summary of the post-verification outcome."""
        return self._last_summary

    @pyqtProperty(str, notify=lastOutcomeChanged)
    def lastOutcome(self) -> str:
        """QML/Qt property for post-verification outcome."""
        return self._last_outcome

    @pyqtProperty(str, notify=lastOutcomeChanged)
    def lastSummary(self) -> str:
        """QML/Qt property for post-verification summary."""
        return self._last_summary

    @pyqtSlot(str, str)
    def set_post_verification_outcome(self, outcome: str, summary: str) -> None:
        """Set post-verification diagnostic outcome and emit lastOutcomeChanged."""
        self._last_outcome = outcome
        self._last_summary = summary
        self.lastOutcomeChanged.emit(outcome, summary)

    @property
    def state(self) -> str:
        """Return current operation state."""
        return self._state

    @property
    def status_text(self) -> str:
        """Return human-readable status text."""
        return self._status_text

    @property
    def stage(self) -> str:
        """Return fine-grained transaction stage."""
        return self._stage

    @property
    def progress(self) -> int:
        """Return current operation progress (0..100 or -1)."""
        return self._progress

    @property
    def is_busy(self) -> bool:
        """Return True if an operation is currently executing."""
        return self._is_busy

    @property
    def waiting_for_input(self) -> bool:
        """Return True if transaction process is paused awaiting interactive response."""
        return self._waiting_for_input

    @property
    def current_prompt_text(self) -> str:
        """Return prompt question text presented by the package manager."""
        return self._current_prompt_text

    @property
    def is_locked(self) -> bool:
        """Return True if pacman database lock file exists without emitting signal."""
        return is_pacman_locked()

    @property
    def can_cancel(self) -> bool:
        """Check if ongoing transaction can be safely cancelled without risking database corruption."""
        if not self._is_busy:
            return False
        if is_pacman_locked():
            return False
        return self._stage in SAFE_CANCEL_STAGES

    # -------------------------------------------------------------------------
    # State Management Helper
    # -------------------------------------------------------------------------

    def _set_state(self, state: str, status_text: str = "") -> None:
        """Update state and status text, emitting stateChanged."""
        self._state = state
        self._status_text = status_text
        self._is_busy = state in ("authenticating", "installing", "removing", "updating", "checking_updates")
        self.stateChanged.emit(self._state, self._status_text)

    def _set_stage(self, stage: str) -> None:
        """Update fine-grained transaction stage, emitting stageChanged."""
        if self._stage != stage:
            self._stage = stage
            self.stageChanged.emit()

    def _set_progress(self, progress: int) -> None:
        """Update progress and emit progressChanged."""
        clamped = max(-1, min(100, progress))
        if self._progress != clamped:
            self._progress = clamped
            self.progressChanged.emit(self._progress)

    def check_lock(self) -> bool:
        """Verify pacman database lock status and emit signal on change."""
        locked = is_pacman_locked()
        if locked != self._last_locked:
            self._last_locked = locked
            self.lockStatusChanged.emit(locked)
        if locked and self._is_busy and self._stage in SAFE_CANCEL_STAGES:
            # Lock appeared during execution; transition out of safe cancel stage
            self._set_stage("committing")
        return locked

    # -------------------------------------------------------------------------
    # Public Transaction Slots & Methods
    # -------------------------------------------------------------------------

    @pyqtSlot(str, str, result=bool)
    def install_package(self, pkg_name: str, repository: str = "official") -> bool:
        """Install a single package by name."""
        return self.install_packages([pkg_name], repository)

    def install_packages(self, pkg_names: Sequence[str], repository: str = "official") -> bool:
        """Safely start installation of packages."""
        if self._is_busy:
            msg = "Uma operação de pacote já está em andamento. Aguarde a conclusão."
            self._emit_failure("install", msg)
            return False

        if self.check_lock():
            msg = "Banco de dados do pacman bloqueado (/var/lib/pacman/db.lck). Aguarde outra operação finalizar."
            self._emit_failure("install", msg)
            return False

        try:
            if repository.lower() in ("aur", "local-aur"):
                cmd = build_safe_yay_install_cmd(pkg_names)
                initial_stage = "downloading"
            else:
                cmd = build_safe_pacman_install_cmd(pkg_names)
                initial_stage = "authenticating"
        except (SecurityViolationError, ValueError, PermissionError) as e:
            msg = f"Falha de validação de segurança: {e}"
            self._emit_failure("install", msg)
            return False

        pkgs_str = ", ".join(pkg_names)
        status = f"Instalando {pkgs_str}..."
        return self._start_transaction(
            "install", list(pkg_names), cmd, status, target_state="installing", initial_stage=initial_stage
        )

    @pyqtSlot(str, result=bool)
    def remove_package(self, pkg_name: str) -> bool:
        """Remove a single package by name."""
        return self.remove_packages([pkg_name])

    def remove_packages(self, pkg_names: Sequence[str], check_reverse_deps: bool = True) -> bool:
        """Safely start removal of packages, strictly blocking protected and dependent packages."""
        if self._is_busy:
            msg = "Uma operação de pacote já está em andamento. Aguarde a conclusão."
            self._emit_failure("remove", msg)
            return False

        if self.check_lock():
            msg = "Banco de dados do pacman bloqueado (/var/lib/pacman/db.lck). Aguarde outra operação finalizar."
            self._emit_failure("remove", msg)
            return False

        try:
            cmd = build_safe_pacman_remove_cmd(pkg_names, check_reverse_deps=check_reverse_deps)
        except (SecurityViolationError, ValueError) as e:
            msg = f"Operação bloqueada por segurança: {e}"
            self._emit_failure("remove", msg)
            return False

        pkgs_str = ", ".join(pkg_names)
        status = f"Removendo {pkgs_str}..."
        return self._start_transaction(
            "remove", list(pkg_names), cmd, status, target_state="removing", initial_stage="authenticating"
        )

    @pyqtSlot(str, result=bool)
    @pyqtSlot(str, str, result=bool)
    @pyqtSlot(str, str, bool, result=bool)
    def update_package(
        self, pkg_name: str, repository: str = "official", redirect_official_to_sysupgrade: bool = True
    ) -> bool:
        """Update a specific package, redirecting official packages to sysupgrade to prevent partial upgrades."""
        return self.update_packages(
            [pkg_name], repository=repository, redirect_official_to_sysupgrade=redirect_official_to_sysupgrade
        )

    def update_packages(
        self,
        pkg_names: Sequence[str],
        repository: str = "official",
        redirect_official_to_sysupgrade: bool = True,
    ) -> bool:
        """Update a set of packages, redirecting official packages to sysupgrade to prevent partial upgrades."""
        if self._is_busy:
            msg = "Uma operação de pacote já está em andamento. Aguarde a conclusão."
            self._emit_failure("update", msg)
            return False

        if self.check_lock():
            msg = "Banco de dados do pacman bloqueado (/var/lib/pacman/db.lck). Aguarde outra operação finalizar."
            self._emit_failure("update", msg)
            return False

        if repository.lower() not in ("aur", "local-aur") and redirect_official_to_sysupgrade:
            self.logLineReceived.emit(
                "[SEGURANÇA ARCH LINUX] Atualizações isoladas de pacotes oficiais (partial upgrades) "
                "não são suportadas no Arch Linux. Encaminhando para atualização completa e sincronizada do sistema (yay -Syu)..."
            )
            return self.update_all()

        try:
            if repository.lower() in ("aur", "local-aur"):
                cmd = build_safe_yay_install_cmd(pkg_names)
                initial_stage = "downloading"
            else:
                cmd = build_safe_pacman_install_cmd(pkg_names)
                initial_stage = "authenticating"
        except (SecurityViolationError, ValueError, PermissionError) as e:
            msg = f"Falha de validação de segurança: {e}"
            self._emit_failure("update", msg)
            return False

        pkgs_str = ", ".join(pkg_names)
        status = f"Atualizando {pkgs_str}..."
        return self._start_transaction(
            "update", list(pkg_names), cmd, status, target_state="updating", initial_stage=initial_stage
        )

    @pyqtSlot(result=bool)
    def update_all(self) -> bool:
        """Perform full system upgrade."""
        if self._is_busy:
            msg = "Uma operação de pacote já está em andamento. Aguarde a conclusão."
            self._emit_failure("update_all", msg)
            return False

        if self.check_lock():
            msg = "Banco de dados do pacman bloqueado (/var/lib/pacman/db.lck). Aguarde outra operação finalizar."
            self._emit_failure("update_all", msg)
            return False

        use_pacman_fallback = False
        if not self.mock_mode:
            yay_bin_path = os.environ.get("REDSHIFT_YAY_BIN", "").strip() or "/usr/bin/yay"
            pacman_bin_path = os.environ.get("REDSHIFT_PACMAN_BIN", "").strip() or "/usr/bin/pacman"
            if not os.path.exists(yay_bin_path) and os.path.exists(pacman_bin_path):
                use_pacman_fallback = True

        try:
            if use_pacman_fallback:
                cmd = build_safe_pacman_sysupgrade_cmd()
                self.logLineReceived.emit(
                    "[AVISO] Gerenciador yay não encontrado no sistema. "
                    "Executando atualização via pacman (apenas repositórios oficiais: pacman -Syu)..."
                )
            else:
                cmd = build_safe_yay_sysupgrade_cmd()
                self.logLineReceived.emit(
                    "[ATUALIZAÇÃO COMPLETA] Atualizando repositórios oficiais e AUR em sincronia (yay -Syu)..."
                )
        except (SecurityViolationError, PermissionError) as e:
            msg = f"Falha de validação de segurança: {e}"
            self._emit_failure("update_all", msg)
            return False

        status = "Atualizando todos os pacotes do sistema..."
        return self._start_transaction(
            "update_all", [], cmd, status, target_state="updating", initial_stage="authenticating"
        )

    @pyqtSlot(result=bool)
    def cancel(self) -> bool:
        """Cancel current running transaction safely without SIGKILL."""
        if not self._is_busy:
            return False

        if not self.can_cancel:
            msg = (
                f"[SEGURANÇA] Cancelamento bloqueado no estágio '{self._stage}': "
                "modificação crítica do banco de pacotes ou lock ativo (/var/lib/pacman/db.lck). "
                "Aguarde a conclusão para preservar a integridade do sistema."
            )
            self.logLineReceived.emit(msg)
            self.cancellationBlocked.emit(msg)
            return False

        self.logLineReceived.emit("[AVISO] Solicitação de cancelamento enviada pelo usuário...")

        if self.mock_mode:
            if self._mock_timer and self._mock_timer.isActive():
                self._mock_timer.stop()
            self._set_progress(0)
            self._set_state("cancelled", "Operação cancelada pelo usuário")
            self._set_stage("idle")
            self._clear_prompt_state()
            cancel_msg = "Operação cancelada pelo usuário."
            self.set_post_verification_outcome("cancelled", cancel_msg)
            self.transactionFinished.emit(False, self._current_action, cancel_msg)
            self._current_action = ""
            self._current_packages = []
            return True

        if self._process and self._process.state() != QProcess.ProcessState.NotRunning:
            # Terminate gracefully via SIGTERM (never SIGKILL)
            self._process.terminate()
            self._set_state("cancelled", "Cancelamento solicitado...")
            return True

        return False

    @pyqtSlot(str, result=bool)
    def send_input(self, text: str) -> bool:
        """Send response string to transaction process stdin."""
        if not self._is_busy:
            return False

        line_to_send = text.strip() + "\n"
        self.logLineReceived.emit(f"[RESPOSTA ENVIADA] {text.strip()}")

        if self.mock_mode:
            self._clear_prompt_state()
            # If mock timer was waiting for user input, advance
            if self._mock_timer and not self._mock_timer.isActive():
                self._mock_timer.start()
            return True

        if self._process and self._process.state() == QProcess.ProcessState.Running:
            self._process.write(line_to_send.encode("utf-8"))
            self._clear_prompt_state()
            return True

        return False

    @pyqtSlot(bool, result=bool)
    def respond_to_prompt(self, accept: bool) -> bool:
        """Quickly answer boolean confirmation prompt (y/n)."""
        return self.send_input("y" if accept else "n")

    def simulate_prompt_for_test(self, prompt_text: str) -> None:
        """Helper for test suites to simulate an interactive prompt."""
        self._waiting_for_input = True
        self._current_prompt_text = prompt_text
        self.promptChanged.emit()

    def _clear_prompt_state(self) -> None:
        """Reset interactive prompt state and notify observers."""
        if self._waiting_for_input or self._current_prompt_text:
            self._waiting_for_input = False
            self._current_prompt_text = ""
            self.promptChanged.emit()

    # -------------------------------------------------------------------------
    # Core Transaction Execution
    # -------------------------------------------------------------------------

    def _start_transaction(
        self,
        action: str,
        packages: list[str],
        cmd: list[str],
        status_text: str,
        target_state: str,
        initial_stage: str = "authenticating",
    ) -> bool:
        """Initiate asynchronous process execution or mock simulation."""
        self._current_action = action
        self._current_packages = packages
        self._stdout_buffer = ""
        self._recent_lines = []
        self._clear_prompt_state()
        self._last_outcome = ""
        self._last_summary = ""
        self.lastOutcomeChanged.emit("", "")
        self._set_progress(-1)
        self._set_stage(initial_stage)
        self._set_state(target_state, status_text)

        cmd_display = " ".join(cmd)
        self.logLineReceived.emit(f"=== Iniciando Operação: {action.upper()} ===")
        self.logLineReceived.emit(f"Comando seguro: {cmd_display}")
        self.logLineReceived.emit(f"Pacotes envolvidos: {', '.join(packages) if packages else 'sistema completo'}")

        if self.mock_mode:
            self._start_mock_simulation(action, packages, cmd)
            return True

        # Ensure a graphical Polkit agent is active in user session (e.g. Caelestia)
        ensure_polkit_agent()

        self._process = QProcess(self)
        self._process.setProgram(cmd[0])
        self._process.setArguments(cmd[1:])

        # Configure environment so pagers (less) don't hang diff review
        env = QProcessEnvironment.systemEnvironment()
        env.insert("GIT_PAGER", "cat")
        env.insert("PAGER", "cat")
        env.insert("SYSTEMD_PAGER", "cat")
        env.insert("TERM", "dumb")
        self._process.setProcessEnvironment(env)

        self._process.readyReadStandardOutput.connect(self._on_stdout_ready)
        self._process.readyReadStandardError.connect(self._on_stderr_ready)
        self._process.finished.connect(self._on_process_finished)

        self._process.start()
        return True

    def _on_stdout_ready(self) -> None:
        """Process output bytes from stdout with line, recent history, and prompt detection."""
        if not self._process:
            return
        data = self._process.readAllStandardOutput().data().decode("utf-8", errors="replace")
        self._stdout_buffer += data

        if "\n" in self._stdout_buffer:
            lines = self._stdout_buffer.split("\n")
            # All complete lines
            for line in lines[:-1]:
                line_str = line.strip()
                if not line_str:
                    continue
                self.logLineReceived.emit(line_str)
                self._recent_lines.append(line_str)
                if len(self._recent_lines) > 4:
                    self._recent_lines.pop(0)
                self._parse_progress_from_log(line_str)
                self._update_stage_from_log(line_str)
            # Retain trailing incomplete line in buffer
            self._stdout_buffer = lines[-1]

        self._check_for_prompts()

    def _on_stderr_ready(self) -> None:
        """Process error lines from stderr."""
        if not self._process:
            return
        data = self._process.readAllStandardError().data().decode("utf-8", errors="replace")
        for line in data.splitlines():
            line_str = line.strip()
            if not line_str:
                continue
            self.logLineReceived.emit(f"[STDERR] {line_str}")
            self._recent_lines.append(line_str)
            if len(self._recent_lines) > 4:
                self._recent_lines.pop(0)
            self._parse_progress_from_log(line_str)
            self._update_stage_from_log(line_str)

        self._check_for_prompts()

    def _check_for_prompts(self) -> None:
        """Evaluate stdout buffer and recent lines for interactive pacman/yay prompts."""
        prompt_found = False
        detected_text = ""
        clean_buf = self._stdout_buffer.strip()

        # 1. Direct match on residual buffer
        if clean_buf:
            m = PROMPT_RE.search(clean_buf)
            if m:
                prompt_found = True
                detected_text = clean_buf
            elif clean_buf in ("==>", ":", "==> [N]one [A]ll [Ab]ort") or clean_buf.startswith("==>"):
                # Check previous 2 recent lines to provide context
                for prev in reversed(self._recent_lines[-2:]):
                    if PROMPT_RE.search(prev):
                        prompt_found = True
                        detected_text = f"{prev} {clean_buf}".strip()
                        break

        # 2. Check last complete line if buffer alone did not trigger
        if not prompt_found and self._recent_lines:
            last_line = self._recent_lines[-1]
            if PROMPT_RE.search(last_line):
                prompt_found = True
                detected_text = last_line

        if prompt_found:
            self._waiting_for_input = True
            self._current_prompt_text = detected_text
            self.promptChanged.emit()

    def _on_process_finished(self, exit_code: int, exit_status: QProcess.ExitStatus) -> None:
        """Handle transaction process termination."""
        action = self._current_action
        is_success = (exit_code == 0) and (exit_status == QProcess.ExitStatus.NormalExit)

        self._set_stage("idle")
        self._clear_prompt_state()

        if is_success:
            self._set_progress(100)
            self._set_state("success", "Operação concluída com sucesso.")
            self.logLineReceived.emit("=== [SUCESSO] Operação finalizada com êxito ===")
            self.set_post_verification_outcome(
                "complete", "Operação concluída com código 0; verificando estado dos pacotes..."
            )
            self.transactionFinished.emit(True, action, "Operação concluída com sucesso.")
        else:
            self._set_progress(0)
            state_label = "cancelled" if self._state == "cancelled" else "error"

            # Check for Polkit dismissal/cancellation or denial
            polkit_denied = (exit_code in (126, 127)) or any(
                any(term in l.lower() for term in ("request dismissed", "not authorized", "authentication failed", "autorização recusada"))
                for l in self._recent_lines
            )
            if polkit_denied:
                msg = f"Autenticação Polkit recusada ou cancelada pelo usuário (código {exit_code})."
                state_label = "cancelled"
            else:
                msg = f"Falha na execução (código de saída: {exit_code})."

            self._set_state(state_label, msg)
            outcome = "cancelled" if state_label == "cancelled" else "failed"
            self.set_post_verification_outcome(outcome, msg)
            self.logLineReceived.emit(f"=== [FALHA] {msg} ===")
            self.transactionFinished.emit(False, action, msg)

        self._current_action = ""
        self._current_packages = []
        self._recent_lines = []
        self._process = None

    def _parse_progress_from_log(self, line: str) -> None:
        """Attempt to extract numeric progress percentage from log line."""
        m = PROGRESS_RE.search(line)
        if m:
            val_str = m.group(1) or m.group(2)
            if val_str:
                try:
                    pct = int(val_str)
                    self._set_progress(pct)
                except ValueError:
                    pass

    def _update_stage_from_log(self, line: str) -> None:
        """Update fine-grained transaction stage dynamically based on tool output."""
        lower = line.lower()

        # Database lock active forces committing stage (cannot cancel)
        if is_pacman_locked():
            self._set_stage("committing")
            return

        # Compiling / AUR build stage
        if any(
            k in lower
            for k in (
                "making package:",
                "criando o pacote:",
                "==> starting build",
                "==> extracting sources",
                "==> validating source",
                "==> starting pkgver",
            )
        ):
            self._set_stage("compiling")
            return

        # Downloading stage
        if any(
            k in lower
            for k in (
                "downloading",
                "baixando",
                "retrieving packages",
                "recuperando pacotes",
                "cloning",
                "clonando",
            )
        ):
            self._set_stage("downloading")
            return

        # Critical database modification stage (commit/install/remove/hooks)
        if any(
            k in lower
            for k in (
                "loading package files",
                "carregando os arquivos",
                "checking for file conflicts",
                "verificando conflitos",
                "processing package changes",
                "processando alterações",
                "installing ",
                "instalando ",
                "upgrading ",
                "atualizando ",
                "removing ",
                "removendo ",
                "running post-transaction hooks",
                "executando hooks",
            )
        ):
            self._set_stage("committing")

    def _emit_failure(self, action: str, error_message: str) -> None:
        """Emit immediate failure when pre-checks reject the transaction."""
        self._set_progress(0)
        self._set_stage("idle")
        self._clear_prompt_state()
        self._set_state("error", error_message)
        self.set_post_verification_outcome("failed", error_message)
        self.logLineReceived.emit(f"[ERRO] {error_message}")
        self.transactionFinished.emit(False, action, error_message)

    # -------------------------------------------------------------------------
    # Mock Simulation (REDSHIFT_STORE_MOCK=1)
    # -------------------------------------------------------------------------

    def _start_mock_simulation(self, action: str, packages: list[str], cmd: list[str]) -> None:
        """Run a realistic multi-step transaction simulation in mock mode."""
        self._mock_step = 0
        self._mock_target_cmd = cmd
        self._mock_timer = QTimer(self)
        self._mock_timer.setInterval(250)
        self._mock_timer.timeout.connect(self._on_mock_step)
        self._mock_timer.start()

    def _on_mock_step(self) -> None:
        """Advance simulated mock transaction step respecting safety stages."""
        self._mock_step += 1
        pkgs_repr = ", ".join(self._current_packages) if self._current_packages else "sistema"

        if self._mock_step == 1:
            self._set_stage("downloading")
            self._set_progress(20)
            self.logLineReceived.emit(f"[MOCK] Baixando pacotes e verificando assinaturas PGP para: {pkgs_repr}...")
        elif self._mock_step == 2:
            self._set_stage("compiling")
            self._set_progress(50)
            self.logLineReceived.emit("[MOCK] Compilando e gerando arquivos de pacote...")
        elif self._mock_step == 3:
            # Critical commit stage where cancel must be blocked!
            self._set_stage("committing")
            self._set_progress(85)
            self.logLineReceived.emit("[MOCK] Executando transação de pacotes no banco local (/var/lib/pacman)...")
        elif self._mock_step >= 4:
            if self._mock_timer:
                self._mock_timer.stop()
            self._set_stage("idle")
            self._set_progress(100)
            action = self._current_action
            self._set_state("success", "Operação mock concluída com sucesso.")
            self.logLineReceived.emit(f"[MOCK SUCESSO] Transação '{action}' em {pkgs_repr} concluída.")
            self.set_post_verification_outcome(
                "complete", "Operação concluída com código 0; verificando estado dos pacotes..."
            )
            self.transactionFinished.emit(True, action, f"Transação '{action}' concluída com sucesso.")
            self._current_action = ""
            self._current_packages = []
