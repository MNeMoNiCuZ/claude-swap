"""Exercise the Windows shortcuts without touching accounts or launching Claude."""

import json
import os
from pathlib import Path
import shutil
import subprocess

import pytest


pytestmark = pytest.mark.skipif(os.name != "nt", reason="Windows batch launchers")


@pytest.fixture
def launcher(tmp_path):
    checkout = tmp_path / "checkout with spaces"
    checkout.mkdir()
    root = Path(__file__).resolve().parents[1]
    for name in ("select.bat", "switch.bat"):
        shutil.copyfile(root / name, checkout / name)
    source = checkout / "src"
    source.mkdir()
    package = source / "claude_swap"
    package.mkdir()
    (package / "__init__.py").write_text("", encoding="utf-8")
    (package / "__main__.py").write_text("from .cli import main\nmain()\n", encoding="utf-8")
    fake_cli = (
        "import json, os, sys\n"
        "from pathlib import Path\n"
        "args = sys.argv[1:]\n"
        "if args == ['--list', '--json']:\n"
        "    print(json.dumps({'accounts': [{'number': 2, 'email': 'user@example.com', "
        "'active': True, 'usageStatus': 'ok', 'usage': {'fiveHour': {'pct': 25}, "
        "'sevenDay': {'pct': 60}}}]}))\n"
        "else:\n"
        "    Path(os.environ['LAUNCH_RECORD']).write_text(json.dumps({'args': args, "
        "'cwd': os.getcwd()}), encoding='utf-8')\n"
        "    sys.exit(int(os.environ.get('LAUNCH_EXIT', '0')))\n"
    )
    (package / "cli.py").write_text(
        "def main():\n" + "".join("    " + line + "\n" for line in fake_cli.splitlines()),
        encoding="utf-8",
    )
    working = tmp_path / "project"
    working.mkdir()
    commands = tmp_path / "Commands"
    commands.mkdir()
    for name in ("select.bat", "switch.bat"):
        shutil.copyfile(checkout / name, commands / name)
    record = tmp_path / "record.json"
    env = dict(os.environ, LAUNCH_RECORD=str(record), PYTHONPATH="",
               CLAUDE_SWAP_ROOT=str(checkout))

    def run(args, input_text="", exit_code=0, script="select.bat", via_commands=False):
        env["LAUNCH_EXIT"] = str(exit_code)
        script_path = (commands if via_commands else checkout) / script
        result = subprocess.run(
            ["cmd.exe", "/d", "/c", "call", str(script_path), *args],
            cwd=working, env=env, input=input_text, capture_output=True,
            text=True, encoding="utf-8", timeout=30,
        )
        data = json.loads(record.read_text(encoding="utf-8")) if record.exists() else None
        return result, data, working

    return run


def test_picker_output_and_session_launch(launcher):
    result, data, working = launcher([], "2\n\n")
    assert result.returncode == 0, result.stderr
    assert "2)  user@example.com  [default]  5h 25%  7d 60%" in result.stdout
    assert data == {"args": ["run", "2"], "cwd": str(working)}


def test_direct_account_and_forwarded_arguments(launcher):
    result, data, _ = launcher(
        ["user@example.com", "--no-share", "--", "--resume", "two words"], "\n",
        exit_code=7,
    )
    assert result.returncode == 7
    assert data["args"] == [
        "run", "user@example.com", "--no-share", "--", "--resume", "two words",
    ]


@pytest.mark.parametrize("choice,code", [("\n", 130), ("99\n\n", 1)])
def test_cancel_and_invalid_choice_do_not_launch(launcher, choice, code):
    result, data, _ = launcher([], choice)
    assert result.returncode == code
    assert data is None


def test_switch_shortcut(launcher):
    result, data, working = launcher([], "\n", script="switch.bat")
    assert result.returncode == 0
    assert data == {"args": ["--switch"], "cwd": str(working)}


def test_standalone_commands_script_preserves_arguments_directory_and_exit_code(launcher):
    result, data, working = launcher(
        ["2", "--", "--resume", "two words"], "\n", exit_code=7, via_commands=True,
    )
    assert result.returncode == 7, result.stderr
    assert data == {
        "args": ["run", "2", "--", "--resume", "two words"], "cwd": str(working),
    }


def test_standalone_switch_selects_default_account(launcher):
    result, data, working = launcher(
        ["2"], "\n", script="switch.bat", via_commands=True,
    )
    assert result.returncode == 0, result.stderr
    assert data == {"args": ["switch", "2"], "cwd": str(working)}


@pytest.mark.parametrize("via_commands", [False, True])
@pytest.mark.parametrize("account", [[], ["2"]])
def test_resume_without_separator(launcher, via_commands, account):
    result, data, _ = launcher(
        account + ["--resume"], "2\n\n", via_commands=via_commands,
    )
    assert result.returncode == 0, result.stderr
    assert data["args"] == ["run", "2", "--", "--resume"]


def test_session_flags_before_implicit_claude_tail(launcher):
    result, data, _ = launcher(
        ["2", "--no-share", "--resume", "two words", "--debug"], "\n",
    )
    assert result.returncode == 0, result.stderr
    assert data["args"] == [
        "run", "2", "--no-share", "--", "--resume", "two words", "--debug",
    ]
