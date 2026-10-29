"""Maintenance Service for Redshift OS health checks and repairs.

Monitors core system components (Caelestia, Quickshell, Qt6 ABI compatibility),
interfaces with 'redshift-doctor' CLI utility when available, and provides
self-healing actions and status properties for the Redshift Store.
"""

from __future__ import annotations

import json
import logging
import os
import shutil
import subprocess
import threading
from pathlib import Path
from typing import Any

from PyQt6.QtCore import QObject, pyqtProperty, pyqtSignal, pyqtSlot

logger = logging.getLogger("redshift_store.maintenance")


class MaintenanceService(QObject):
    """Monitors system health and manages repair routines for Redshift OS."""

    maintenanceChanged = pyqtSignal()
    isRepairingChanged = pyqtSignal()
    repairFinished = pyqtSignal(bool, str)  # (success: bool, message: str)

    def __init__(self, parent: QObject | None = None, mock_mode: bool | None = None) -> None:
        super().__init__(parent)

        if mock_mode is None:
            mock_mode = os.environ.get("REDSHIFT_STORE_MOCK", "").lower() in ("1", "true", "yes")
        self._mock_mode = mock_mode

        self._maintenance_required: bool = False
        self._maintenance_title: str = ""
        self._maintenance_message: str = ""
        self._maintenance_cause: str = ""
        self._is_repairing: bool = False

    # -------------------------------------------------------------------------
    # Properties
    # -------------------------------------------------------------------------

    @pyqtProperty(bool, notify=maintenanceChanged)
    def maintenance_required(self) -> bool:
        return self._maintenance_required

    @pyqtProperty(str, notify=maintenanceChanged)
    def maintenance_title(self) -> str:
        return self._maintenance_title

    @pyqtProperty(str, notify=maintenanceChanged)
    def maintenance_message(self) -> str:
        return self._maintenance_message

    @pyqtProperty(str, notify=maintenanceChanged)
    def maintenance_cause(self) -> str:
        return self._maintenance_cause

    @pyqtProperty(bool, notify=isRepairingChanged)
    def is_repairing(self) -> bool:
        return self._is_repairing

    # -------------------------------------------------------------------------
    # Public Methods / Slots
    # -------------------------------------------------------------------------

    @pyqtSlot()
    def check_health(self, async_mode: bool = False) -> None:
        """Run health diagnosis on core Redshift OS components."""
        if async_mode:
            thread = threading.Thread(target=self._perform_health_check, daemon=True)
            thread.start()
        else:
            self._perform_health_check()

    @pyqtSlot(str)
    def repair_component(self, component: str = "caelestia") -> None:
        """Trigger automated component repair via redshift-doctor or fallback."""
        if self._is_repairing:
            return

        self._is_repairing = True
        self.isRepairingChanged.emit()

        thread = threading.Thread(target=self._perform_repair, args=(component,), daemon=True)
        thread.start()

    # -------------------------------------------------------------------------
    # Internal Diagnosis and Repair Logic
    # -------------------------------------------------------------------------

    @staticmethod
    def _find_doctor_binary() -> str | None:
        """Locate redshift-doctor binary if available."""
        from_env = os.environ.get("REDSHIFT_DOCTOR_BIN")
        if from_env and os.path.isfile(from_env) and os.access(from_env, os.X_OK):
            return from_env

        which_bin = shutil.which("redshift-doctor")
        if which_bin and os.path.isfile(which_bin) and os.access(which_bin, os.X_OK):
            return which_bin

        home = Path.home()
        candidates = [
            home / ".local" / "bin" / "redshift-doctor",
            Path("/usr/local/bin/redshift-doctor"),
            Path("/usr/bin/redshift-doctor"),
        ]
        for cand in candidates:
            if cand.is_file() and os.access(cand, os.X_OK):
                return str(cand)

        return None

    def _perform_health_check(self) -> None:
        """Execute diagnostic checks across redshift-doctor and native fallbacks."""
        # 1. Environment variable overrides (for automated testing / mock control)
        env_forced = os.environ.get("REDSHIFT_MAINTENANCE_REQUIRED")
        if env_forced is not None:
            is_req = env_forced.lower() in ("1", "true", "yes")
            self._set_state(
                required=is_req,
                title=os.environ.get("REDSHIFT_MAINTENANCE_TITLE", "Reparo do Redshift OS Necessário" if is_req else ""),
                message=os.environ.get(
                    "REDSHIFT_MAINTENANCE_MESSAGE",
                    "Um componente do Redshift OS precisa de reparo após a atualização. O frontend Caelestia está temporariamente indisponível."
                    if is_req else "",
                ),
                cause=os.environ.get(
                    "REDSHIFT_MAINTENANCE_CAUSE",
                    "Falha simulada via variável de ambiente para diagnóstico." if is_req else "",
                ),
            )
            return

        # 2. Check for external redshift-doctor binary
        doctor_bin = self._find_doctor_binary()

        if doctor_bin and not self._mock_mode:
            try:
                proc = subprocess.run(
                    [doctor_bin, "--check", "caelestia", "--json"],
                    capture_output=True,
                    text=True,
                    timeout=8,
                )
                try:
                    data = json.loads(proc.stdout)
                    errors = [
                        f"• {c.get('name')}: {c.get('message')}"
                        for c in data.get("checks", [])
                        if c.get("status") == "ERROR"
                    ]
                    if errors or proc.returncode != 0:
                        cause_msg = "\n".join(errors) if errors else (proc.stdout or proc.stderr or "").strip()
                        self._set_state(
                            required=True,
                            title="Reparo do Redshift OS Necessário",
                            message="Um componente do Redshift OS precisa de reparo após a atualização. O frontend Caelestia está temporariamente indisponível.",
                            cause=cause_msg or "Diagnóstico do redshift-doctor indicou falha em componentes essenciais.",
                        )
                        return
                    else:
                        self._set_state(required=False, title="", message="", cause="")
                        return
                except Exception:
                    # Fallback para parsing em modo texto
                    if proc.returncode != 0:
                        output_text = (proc.stdout or proc.stderr or "").strip()
                        self._set_state(
                            required=True,
                            title="Reparo do Redshift OS Necessário",
                            message="Um componente do Redshift OS precisa de reparo após a atualização. O frontend Caelestia está temporariamente indisponível.",
                            cause=output_text or "Diagnóstico do redshift-doctor indicou falha em componentes essenciais.",
                        )
                        return
                    else:
                        self._set_state(required=False, title="", message="", cause="")
                        return
            except Exception as e:
                logger.warning("Error running redshift-doctor: %s", e)

        # 3. Native fallback inspection: verify Caelestia and Quickshell health
        if self._mock_mode:
            # Em mock mode sem override, sistema permanece saudável
            self._set_state(required=False, title="", message="", cause="")
            return

        home = Path.home()
        cael_config = home / ".config" / "quickshell" / "caelestia-hybrid"

        # Se o perfil caelestia-hybrid estiver configurado, validar integridade
        if cael_config.is_dir():
            qml_candidates = []
            env_qml = os.environ.get("CAELESTIA_QML_PATH")
            if env_qml:
                qml_candidates.append(Path(env_qml))

            qml_candidates.extend([
                Path("/usr/lib/qt6/qml"),
                Path("/usr/local/lib/qt6/qml"),
                home / ".local" / "share" / "quickshell" / "qml",
                home / ".local" / "lib" / "qt6" / "qml",
            ])

            found_plugin_dir: Path | None = None
            found_so_path: Path | None = None

            for cand in qml_candidates:
                cael_dir = cand / "Caelestia"
                qmldir_file = cael_dir / "qmldir"
                if qmldir_file.is_file() and os.access(qmldir_file, os.R_OK):
                    so_coreplugin = cael_dir / "libcaelestia-coreplugin.so"
                    so_libcore = cael_dir / "lib" / "libcaelestia-core.so"
                    if so_coreplugin.is_file() and os.access(so_coreplugin, os.R_OK):
                        found_plugin_dir = cand
                        found_so_path = so_coreplugin
                        break
                    elif so_libcore.is_file() and os.access(so_libcore, os.R_OK):
                        found_plugin_dir = cand
                        found_so_path = so_libcore
                        break

            # Nível 1: Verificação de Instalação
            if not found_plugin_dir or not found_so_path:
                self._set_state(
                    required=True,
                    title="Plugin Caelestia Incompleto ou Ausente",
                    message="Um componente do Redshift OS precisa de reparo após a atualização. O frontend Caelestia está temporariamente indisponível.",
                    cause="Instalação incompleta ou ausente: plugin nativo Caelestia não encontrado. Execute 'redshift-doctor --check caelestia'.",
                )
                return

            # Nível 2: Verificação de Compatibilidade via ldd
            ldd_bin = shutil.which("ldd")
            if ldd_bin and found_so_path:
                try:
                    proc_ldd = subprocess.run(
                        [ldd_bin, "-r", str(found_so_path)],
                        capture_output=True,
                        text=True,
                        timeout=5,
                    )
                    combined_out = (proc_ldd.stdout or "") + "\n" + (proc_ldd.stderr or "")
                    unresolved = [
                        line.strip()
                        for line in combined_out.splitlines()
                        if "undefined symbol" in line.lower() or "not found" in line.lower()
                    ]
                    if unresolved:
                        detail_msg = "\n".join(unresolved[:10])
                        self._set_state(
                            required=True,
                            title="Incompatibilidade de Linker Qt6",
                            message="Um componente do Redshift OS precisa de reparo após a atualização. O frontend Caelestia está temporariamente indisponível.",
                            cause=f"Incompatibilidade detectada entre Caelestia e Qt6/Quickshell. Execute 'redshift-doctor --repair caelestia'.\n\nDetalhes:\n{detail_msg}",
                        )
                        return
                except Exception as e:
                    logger.warning("Error checking ldd for %s: %s", found_so_path, e)

        # Se tudo estiver normal
        self._set_state(required=False, title="", message="", cause="")

    def _perform_repair(self, component: str) -> None:
        """Execute repair action for specified component."""
        logger.info("Starting repair routine for component: %s", component)

        success = False
        msg = ""

        if self._mock_mode:
            # Em mock mode, simula sucesso para testes determinísticos
            success = True
            msg = f"[MOCK] Reparo do componente '{component}' finalizado com sucesso."
            self._set_state(required=False, title="", message="", cause="")
        else:
            doctor_bin = self._find_doctor_binary()
            if doctor_bin:
                try:
                    proc = subprocess.run(
                        [doctor_bin, "--repair", component, "-y"],
                        capture_output=True,
                        text=True,
                        timeout=45,
                    )
                    success = (proc.returncode == 0)
                    msg = proc.stdout.strip() if success else (proc.stderr or proc.stdout).strip()
                except Exception as e:
                    success = False
                    msg = f"Erro ao executar redshift-doctor: {e}"
            else:
                # Fallback gracioso quando redshift-doctor não está instalado no PATH
                success = False
                msg = (
                    f"Utilitário 'redshift-doctor' não foi localizado no sistema para reparar '{component}'. "
                    "Instale o pacote redshift-doctor ou reinstale illogical-impulse-caelestia-plugin."
                )

        self._is_repairing = False
        self.isRepairingChanged.emit()

        # Reavaliar saúde do sistema
        self._perform_health_check()
        self.repairFinished.emit(success, msg)

    def _set_state(self, required: bool, title: str, message: str, cause: str) -> None:
        """Update internal state and emit notification signal if changed."""
        changed = (
            self._maintenance_required != required
            or self._maintenance_title != title
            or self._maintenance_message != message
            or self._maintenance_cause != cause
        )
        self._maintenance_required = required
        self._maintenance_title = title
        self._maintenance_message = message
        self._maintenance_cause = cause

        if changed:
            self.maintenanceChanged.emit()
