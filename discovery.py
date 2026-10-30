"""Local discovery distinguishes available tools/journals from verified account access."""
import shutil
from codex_account import executable
from runtime import provider_home


def discover(settings):
    try:
        codex_installed = bool(executable(settings['codex']))
    except FileNotFoundError:
        codex_installed = False
    codex_journals = (provider_home(settings['codex']['home'], 'CODEX_HOME', '.codex') / 'sessions').is_dir()
    claude_journals = (provider_home(settings['claude']['home'], 'CLAUDE_CONFIG_DIR', '.claude') / 'projects').is_dir()
    return {
        'codex_installed': codex_installed, 'codex_journals': codex_journals,
        'claude_installed': bool(shutil.which('claude.exe') or shutil.which('claude.cmd') or shutil.which('claude')),
        'claude_journals': claude_journals,
        'claude_external': settings['claude'].get('source') == 'external',
    }
