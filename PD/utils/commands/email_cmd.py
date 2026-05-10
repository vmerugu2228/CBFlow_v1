#!/usr/bin/env python3
"""
CBflow Email Notification System
Sends formatted email reports for run events: status, creation, summary,
checklist, reminders, release updates.
Uses Python stdlib (smtplib + email) — no external dependencies.
"""

import argparse
import json
import os
import re
import smtplib
import socket
import subprocess
import sys
from datetime import datetime
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText
from email.mime.base import MIMEBase
from email import encoders
from pathlib import Path

# ── Logging ──────────────────────────────────────────────────────────────────
try:
    from .logging_config import get_logger
    logger = get_logger('cbflow.email')
except Exception:
    import logging
    logger = logging.getLogger('cbflow.email')

# ── Email Configuration ─────────────────────────────────────────────────────

def load_email_config(run_dir: str = None) -> dict:
    """Load email config from flow_config or environment."""
    config = {
        'smtp_server': os.environ.get('CBFLOW_SMTP_SERVER', 'localhost'),
        'smtp_port': int(os.environ.get('CBFLOW_SMTP_PORT', '25')),
        'smtp_auth': os.environ.get('CBFLOW_SMTP_AUTH', 'false').lower() == 'true',
        'smtp_user': os.environ.get('CBFLOW_SMTP_USER', ''),
        'smtp_password': os.environ.get('CBFLOW_SMTP_PASSWORD', ''),
        'smtp_tls': os.environ.get('CBFLOW_SMTP_TLS', 'false').lower() == 'true',
        'from_address': os.environ.get('CBFLOW_EMAIL_FROM', f'{os.environ.get("USER", "cbflow")}@{socket.getfqdn()}'),
        'reply_to': os.environ.get('CBFLOW_EMAIL_REPLY_TO', ''),
        'cc': os.environ.get('CBFLOW_EMAIL_CC', ''),
        'signature': os.environ.get('CBFLOW_EMAIL_SIGNATURE', 'CBflow Automation'),
        'enabled': os.environ.get('CBFLOW_EMAIL_ENABLED', 'true').lower() == 'true',
    }

    # Try loading from TCL config
    if run_dir:
        _load_tcl_email_config(run_dir, config)

    return config


def _load_tcl_email_config(run_dir: str, config: dict):
    """Parse email settings from .run.cbflow.tcl or flow_config."""
    env_file = os.path.join(run_dir, '.run.cbflow.tcl')
    if not os.path.exists(env_file):
        return
    try:
        with open(env_file) as f:
            for line in f:
                m = re.match(r'set\s+flow\(email,(\w+)\)\s+"?([^"]*)"?\s*$', line.strip())
                if m:
                    key, val = m.group(1), m.group(2).strip('"')
                    if key == 'smtp_server':    config['smtp_server'] = val
                    elif key == 'smtp_port':    config['smtp_port'] = int(val)
                    elif key == 'from':         config['from_address'] = val
                    elif key == 'cc':           config['cc'] = val
                    elif key == 'recipients':   config['default_recipients'] = val
                    elif key == 'signature':    config['signature'] = val
                    elif key == 'enabled':      config['enabled'] = val.lower() == 'true'
    except Exception as e:
        logger.debug(f"Could not parse email config from {env_file}: {e}")


# ── Run Data Collection ──────────────────────────────────────────────────────

def collect_run_info(run_dir: str) -> dict:
    """Collect run metadata for email templates."""
    info = {
        'run_dir': run_dir,
        'run_name': os.path.basename(run_dir),
        'user': os.environ.get('USER', 'unknown'),
        'hostname': socket.gethostname(),
        'timestamp': datetime.now().strftime('%Y-%m-%d %H:%M:%S'),
        'date': datetime.now().strftime('%Y-%m-%d'),
        'flow_type': '',
        'design_name': '',
        'project_name': '',
        'tech_node': '',
        'release_version': '',
        'stages': [],
        'stage_status': {},
        'qor_summary': {},
    }

    # Parse run name for flow type
    run_name = info['run_name']
    m = re.match(r'P\d+_run_(\w+)_run\d+', run_name)
    if m:
        info['flow_type'] = m.group(1)

    # Read .run.cbflow.tcl for design/project info
    env_file = os.path.join(run_dir, '.run.cbflow.tcl')
    if os.path.exists(env_file):
        _parse_env_file(env_file, info)

    # Collect stage status from stamps
    _collect_stage_status(run_dir, info)

    # Collect QoR from reports
    _collect_qor_summary(run_dir, info)

    return info


def _parse_env_file(env_file: str, info: dict):
    """Parse .run.cbflow.tcl for key variables."""
    try:
        with open(env_file) as f:
            for line in f:
                line = line.strip()
                for pattern, key in [
                    (r'set\s+flow\(design_name\)\s+"([^"]+)"', 'design_name'),
                    (r'set\s+project\(name\)\s+"([^"]+)"', 'project_name'),
                    (r'set\s+::env\(TECH_NAME\)\s+"([^"]+)"', 'tech_node'),
                    (r'set\s+::env\(CBFLOW_RELEASE\)\s+"([^"]+)"', 'release_version'),
                    (r'set\s+flow\(type\)\s+"([^"]+)"', 'flow_type'),
                ]:
                    m = re.match(pattern, line)
                    if m and not info.get(key):
                        info[key] = m.group(1)
    except Exception:
        pass


def _collect_stage_status(run_dir: str, info: dict):
    """Collect stage completion status from .stamps directory."""
    stamps_dir = os.path.join(run_dir, '.stamps')
    if not os.path.isdir(stamps_dir):
        return

    for stamp_file in sorted(Path(stamps_dir).glob('*')):
        stage_name = stamp_file.name
        try:
            mtime = datetime.fromtimestamp(stamp_file.stat().st_mtime)
            with open(stamp_file) as f:
                content = f.read().strip()
            status = 'PASS' if 'PASS' in content.upper() or 'DONE' in content.upper() else 'DONE'
        except Exception:
            status = 'DONE'
            mtime = datetime.now()

        info['stage_status'][stage_name] = {
            'status': status,
            'timestamp': mtime.strftime('%Y-%m-%d %H:%M:%S'),
        }
        if stage_name not in info['stages']:
            info['stages'].append(stage_name)


def _collect_qor_summary(run_dir: str, info: dict):
    """Collect QoR metrics from report files."""
    qor = {}
    # Search for report_qor files in work directories
    work_dir = os.path.join(run_dir, 'work')
    if not os.path.isdir(work_dir):
        return

    for report_file in Path(work_dir).rglob('reports/report_qor.rpt'):
        stage = report_file.parent.parent.name
        try:
            with open(report_file) as f:
                content = f.read()
            # Extract key metrics
            wns_m = re.search(r'WNS\s*\(setup\)\s*:\s*([-\d.]+)', content)
            tns_m = re.search(r'TNS\s*\(setup\)\s*:\s*([-\d.]+)', content)
            area_m = re.search(r'Cell Area.*?:\s*([\d.]+)', content)
            if wns_m: qor.setdefault(stage, {})['wns'] = wns_m.group(1)
            if tns_m: qor.setdefault(stage, {})['tns'] = tns_m.group(1)
            if area_m: qor.setdefault(stage, {})['area'] = area_m.group(1)
        except Exception:
            pass

    info['qor_summary'] = qor


# ── Email Templates ──────────────────────────────────────────────────────────

def template_run_creation(info: dict, user_config_vars: dict = None) -> tuple:
    """Template: New run created notification."""
    subject = f"[CBflow] Run Created: {info['run_name']} ({info['flow_type']})"

    vars_table = ""
    if user_config_vars:
        vars_table = "\n  Key User Config Variables:\n"
        vars_table += "  " + "-" * 60 + "\n"
        for k, v in sorted(user_config_vars.items()):
            vars_table += f"  {k:40s} = {v}\n"

    body = f"""
  CBflow Run Created
  {'=' * 60}

  Run Name      : {info['run_name']}
  Flow Type     : {info['flow_type']}
  Design        : {info['design_name']}
  Project       : {info['project_name']}
  Technology    : {info['tech_node']}
  Release       : {info['release_version']}
  Created By    : {info['user']}
  Host          : {info['hostname']}
  Timestamp     : {info['timestamp']}
  Run Directory : {info['run_dir']}
{vars_table}
  {'=' * 60}
  {info.get('signature', 'CBflow Automation')}
"""
    return subject, body


def template_run_status(info: dict) -> tuple:
    """Template: Run status update."""
    total = len(info['stage_status'])
    passed = sum(1 for s in info['stage_status'].values() if s['status'] in ('PASS', 'DONE'))
    failed = sum(1 for s in info['stage_status'].values() if s['status'] == 'FAIL')
    pending = total - passed - failed

    overall = "RUNNING" if pending > 0 else ("PASSED" if failed == 0 else "FAILED")
    subject = f"[CBflow] Run Status [{overall}]: {info['run_name']}"

    stage_table = ""
    for stage, data in info['stage_status'].items():
        icon = "PASS" if data['status'] in ('PASS', 'DONE') else "FAIL" if data['status'] == 'FAIL' else "----"
        stage_table += f"    [{icon}]  {stage:30s}  {data['timestamp']}\n"

    body = f"""
  CBflow Run Status Report
  {'=' * 60}

  Run Name      : {info['run_name']}
  Flow Type     : {info['flow_type']}
  Design        : {info['design_name']}
  Status        : {overall}
  Progress      : {passed}/{total} stages complete
  Timestamp     : {info['timestamp']}

  Stage Status:
  {'-' * 60}
{stage_table}
  {'-' * 60}
  Passed: {passed}  |  Failed: {failed}  |  Pending: {pending}

  Run Directory : {info['run_dir']}
  {'=' * 60}
  {info.get('signature', 'CBflow Automation')}
"""
    return subject, body


def template_run_summary(info: dict) -> tuple:
    """Template: Run completion summary with QoR."""
    subject = f"[CBflow] Run Summary: {info['run_name']} ({info['flow_type']})"

    qor_table = ""
    if info['qor_summary']:
        qor_table = "\n  QoR Summary:\n"
        qor_table += f"  {'Stage':20s} {'WNS (ns)':>12s} {'TNS (ns)':>12s} {'Area':>14s}\n"
        qor_table += "  " + "-" * 60 + "\n"
        for stage, metrics in info['qor_summary'].items():
            wns = metrics.get('wns', 'N/A')
            tns = metrics.get('tns', 'N/A')
            area = metrics.get('area', 'N/A')
            qor_table += f"  {stage:20s} {wns:>12s} {tns:>12s} {area:>14s}\n"

    total = len(info['stage_status'])
    passed = sum(1 for s in info['stage_status'].values() if s['status'] in ('PASS', 'DONE'))

    body = f"""
  CBflow Run Summary
  {'=' * 60}

  Run Name      : {info['run_name']}
  Flow Type     : {info['flow_type']}
  Design        : {info['design_name']}
  Project       : {info['project_name']}
  Technology    : {info['tech_node']}
  Release       : {info['release_version']}
  Completed By  : {info['user']}
  Host          : {info['hostname']}
  Timestamp     : {info['timestamp']}

  Completion    : {passed}/{total} stages
{qor_table}
  Run Directory : {info['run_dir']}
  {'=' * 60}
  {info.get('signature', 'CBflow Automation')}
"""
    return subject, body


def template_checklist_summary(info: dict, checklist_data: dict = None) -> tuple:
    """Template: Exit milestone checklist summary."""
    subject = f"[CBflow] Checklist Summary: {info['run_name']}"

    checks_text = ""
    if checklist_data:
        milestone = checklist_data.get('milestone', 'unknown')
        checks = checklist_data.get('checks', [])
        total_checks = len(checks)
        passed_checks = sum(1 for c in checks if c.get('status') == 'PASS')
        waived_checks = sum(1 for c in checks if c.get('status') == 'WAIVED')

        checks_text = f"""
  Milestone     : {milestone}
  Total Checks  : {total_checks}
  Passed        : {passed_checks}
  Waived        : {waived_checks}
  Failed        : {total_checks - passed_checks - waived_checks}

  Check Details:
  {'-' * 60}
"""
        for c in checks:
            status = c.get('status', '----')
            name = c.get('name', 'unnamed')
            checks_text += f"    [{status:6s}]  {name}\n"

    body = f"""
  CBflow Exit Milestone Checklist
  {'=' * 60}

  Run Name      : {info['run_name']}
  Flow Type     : {info['flow_type']}
  Design        : {info['design_name']}
{checks_text}
  {'=' * 60}
  {info.get('signature', 'CBflow Automation')}
"""
    return subject, body


def template_reminder(info: dict, message: str = "", due_date: str = "") -> tuple:
    """Template: Reminder notification."""
    subject = f"[CBflow] Reminder: {info['run_name']} - {message[:50]}"

    body = f"""
  CBflow Reminder
  {'=' * 60}

  Run Name      : {info['run_name']}
  Flow Type     : {info['flow_type']}
  Design        : {info['design_name']}
  Due Date      : {due_date if due_date else 'N/A'}

  Message:
  {'-' * 60}
  {message}
  {'-' * 60}

  Run Directory : {info['run_dir']}
  {'=' * 60}
  {info.get('signature', 'CBflow Automation')}
"""
    return subject, body


def template_release_update(info: dict, release_info: dict = None) -> tuple:
    """Template: Release update / tag notification."""
    subject = f"[CBflow] Release Update: {info.get('release_version', 'unknown')}"

    rel_details = ""
    if release_info:
        rel_details = f"""
  Release Version  : {release_info.get('version', 'N/A')}
  Release Date     : {release_info.get('date', 'N/A')}
  Tagged By        : {release_info.get('tagged_by', 'N/A')}

  Components Updated:
  {'-' * 60}
"""
        for comp, ver in release_info.get('components', {}).items():
            rel_details += f"    {comp:40s}  v{ver}\n"

        if release_info.get('changelog'):
            rel_details += f"""
  Changelog:
  {'-' * 60}
  {release_info['changelog']}
"""

    body = f"""
  CBflow Release Update
  {'=' * 60}

  Project       : {info['project_name']}
{rel_details}
  {'=' * 60}
  {info.get('signature', 'CBflow Automation')}
"""
    return subject, body


# ── HTML Templates ───────────────────────────────────────────────────────────

def render_html_email(subject: str, text_body: str, info: dict) -> str:
    """Convert text body to styled HTML email."""
    # Convert text body lines to HTML
    lines = text_body.strip().split('\n')
    html_lines = []
    for line in lines:
        stripped = line.strip()
        if '=' * 20 in stripped:
            html_lines.append('<hr style="border:2px solid #1a56db;">')
        elif '-' * 20 in stripped:
            html_lines.append('<hr style="border:1px solid #e5e7eb;">')
        elif stripped.startswith('[PASS]') or stripped.startswith('[DONE]'):
            html_lines.append(f'<div style="color:#059669;font-family:monospace;">{stripped}</div>')
        elif stripped.startswith('[FAIL]'):
            html_lines.append(f'<div style="color:#dc2626;font-family:monospace;">{stripped}</div>')
        elif ':' in stripped and not stripped.startswith(' '):
            parts = stripped.split(':', 1)
            html_lines.append(f'<div><strong>{parts[0]}:</strong>{parts[1] if len(parts) > 1 else ""}</div>')
        else:
            html_lines.append(f'<div style="font-family:monospace;white-space:pre;">{line}</div>')

    body_html = '\n'.join(html_lines)

    return f"""<!DOCTYPE html>
<html>
<head><meta charset="utf-8"><title>{subject}</title></head>
<body style="font-family:'Segoe UI',Arial,sans-serif;max-width:700px;margin:0 auto;padding:20px;background:#f9fafb;">
  <div style="background:#1a56db;color:white;padding:15px 20px;border-radius:8px 8px 0 0;">
    <h2 style="margin:0;font-size:18px;">{subject}</h2>
    <div style="font-size:12px;opacity:0.8;">{info.get('timestamp', '')}</div>
  </div>
  <div style="background:white;padding:20px;border:1px solid #e5e7eb;border-radius:0 0 8px 8px;">
    {body_html}
  </div>
  <div style="text-align:center;padding:10px;font-size:11px;color:#6b7280;">
    {info.get('signature', 'CBflow Automation')} | {info.get('hostname', '')}
  </div>
</body>
</html>"""


# ── Email Sending ────────────────────────────────────────────────────────────

def send_email(config: dict, recipients: list, subject: str, text_body: str,
               html_body: str = None, attachments: list = None) -> bool:
    """Send email via SMTP."""
    if not config.get('enabled', True):
        logger.info("Email notifications disabled")
        return False

    if not recipients:
        logger.error("No recipients specified")
        return False

    msg = MIMEMultipart('alternative')
    msg['From'] = config['from_address']
    msg['To'] = ', '.join(recipients)
    msg['Subject'] = subject
    if config.get('reply_to'):
        msg['Reply-To'] = config['reply_to']
    if config.get('cc'):
        msg['Cc'] = config['cc']

    # Attach text body
    msg.attach(MIMEText(text_body, 'plain'))

    # Attach HTML body
    if html_body:
        msg.attach(MIMEText(html_body, 'html'))

    # Attach files
    if attachments:
        for filepath in attachments:
            if os.path.exists(filepath):
                with open(filepath, 'rb') as f:
                    part = MIMEBase('application', 'octet-stream')
                    part.set_payload(f.read())
                    encoders.encode_base64(part)
                    part.add_header('Content-Disposition', f'attachment; filename="{os.path.basename(filepath)}"')
                    msg.attach(part)

    all_recipients = list(recipients)
    if config.get('cc'):
        all_recipients.extend([r.strip() for r in config['cc'].split(',') if r.strip()])

    try:
        if config.get('smtp_tls'):
            server = smtplib.SMTP(config['smtp_server'], config['smtp_port'])
            server.starttls()
        else:
            server = smtplib.SMTP(config['smtp_server'], config['smtp_port'])

        if config.get('smtp_auth') and config.get('smtp_user'):
            server.login(config['smtp_user'], config['smtp_password'])

        server.sendmail(config['from_address'], all_recipients, msg.as_string())
        server.quit()
        logger.info(f"Email sent to {', '.join(recipients)}: {subject}")
        return True
    except Exception as e:
        logger.error(f"Failed to send email: {e}")
        return False


# ── User Config Parser ───────────────────────────────────────────────────────

def parse_user_config_vars(run_dir: str) -> dict:
    """Parse key variables from user_config.tcl for email display."""
    user_config = os.path.join(run_dir, 'setup', 'user_config.tcl')
    vars_dict = {}
    if not os.path.exists(user_config):
        return vars_dict

    try:
        with open(user_config) as f:
            for line in f:
                line = line.strip()
                if line.startswith('#') or not line:
                    continue
                m = re.match(r'set\s+(\w+\([^)]+\))\s+"?([^"]*)"?\s*$', line)
                if m:
                    vars_dict[m.group(1)] = m.group(2).strip('"')
    except Exception:
        pass
    return vars_dict


# ── CLI Command Functions ────────────────────────────────────────────────────

def cmd_email(args: argparse.Namespace) -> int:
    """Send CBflow email notification."""
    run_dir = os.getcwd()

    # Load config
    email_config = load_email_config(run_dir)
    info = collect_run_info(run_dir)
    info['signature'] = email_config.get('signature', 'CBflow Automation')

    recipients = [r.strip() for r in args.recipients.split(',')]

    # Select template
    template_type = args.template

    if template_type == 'run-creation':
        user_vars = parse_user_config_vars(run_dir)
        subject, body = template_run_creation(info, user_vars)
    elif template_type == 'run-status':
        subject, body = template_run_status(info)
    elif template_type == 'run-summary':
        subject, body = template_run_summary(info)
    elif template_type == 'checklist':
        checklist_data = _load_checklist_data(run_dir, args)
        subject, body = template_checklist_summary(info, checklist_data)
    elif template_type == 'reminder':
        subject, body = template_reminder(info,
                                          message=args.message or "Please review the run status",
                                          due_date=args.due_date or "")
    elif template_type == 'release-update':
        release_info = _load_release_info(run_dir)
        subject, body = template_release_update(info, release_info)
    else:
        logger.error(f"Unknown template: {template_type}")
        return 1

    # Custom subject override
    if args.subject:
        subject = args.subject

    # Generate HTML
    html_body = render_html_email(subject, body, info)

    # Attachments
    attachments = args.attach if args.attach else []

    # Preview mode
    if args.preview:
        print(f"\n{'=' * 70}")
        print(f"  TO: {', '.join(recipients)}")
        print(f"  SUBJECT: {subject}")
        print(f"{'=' * 70}")
        print(body)
        if args.html:
            html_file = os.path.join(run_dir, 'email_preview.html')
            with open(html_file, 'w') as f:
                f.write(html_body)
            print(f"\n  HTML preview saved: {html_file}")
        return 0

    # Send
    success = send_email(email_config, recipients, subject, body, html_body, attachments)
    return 0 if success else 1


def _load_checklist_data(run_dir: str, args) -> dict:
    """Load checklist data for email template."""
    checklist_file = os.path.join(run_dir, 'checklist_status.json')
    if os.path.exists(checklist_file):
        try:
            with open(checklist_file) as f:
                return json.load(f)
        except Exception:
            pass
    return {'milestone': getattr(args, 'milestone', 'M0'), 'checks': []}


def _load_release_info(run_dir: str) -> dict:
    """Load release info for email template."""
    release_info = {}
    # Try to find MANIFEST.json in releases
    flow_dir = os.environ.get('FLOW_DIR', '')
    if flow_dir:
        releases_dir = os.path.join(flow_dir, 'releases')
        if os.path.isdir(releases_dir):
            versions = sorted(Path(releases_dir).iterdir(), reverse=True)
            if versions:
                manifest = versions[0] / 'MANIFEST.json'
                if manifest.exists():
                    try:
                        with open(manifest) as f:
                            release_info = json.load(f)
                    except Exception:
                        pass
                changelog = versions[0] / 'CHANGELOG.md'
                if changelog.exists():
                    try:
                        with open(changelog) as f:
                            release_info['changelog'] = f.read()[:500]
                    except Exception:
                        pass
    return release_info


# ── Parser ───────────────────────────────────────────────────────────────────

def create_parser(subparsers=None):
    """Create email command parser."""
    _fmt = argparse.RawDescriptionHelpFormatter

    if subparsers:
        parser = subparsers.add_parser('email',
            help='Send email notifications',
            formatter_class=_fmt,
            description="""Send CBflow email notifications with formatted templates.

Templates:
  run-creation    New run created (includes user_config variables)
  run-status      Current run stage status
  run-summary     Run completion summary with QoR metrics
  checklist       Exit milestone checklist summary
  reminder        Custom reminder notification
  release-update  Release version update notification

Examples:
  cbflow run email --to user@company.com --template run-status
  cbflow run email --to team@company.com --template run-summary --attach reports/qor.rpt
  cbflow run email --to user@company.com --template reminder --message "Review timing" --due 2026-05-15
  cbflow run email --to user@company.com --template run-creation --preview
""")
    else:
        parser = argparse.ArgumentParser(prog='cbflow run email',
            formatter_class=_fmt, description='Send CBflow email notifications')

    parser.add_argument('--to', '--recipients', dest='recipients', required=True,
                        help='Comma-separated list of email recipients')
    parser.add_argument('--template', '-t', required=True,
                        choices=['run-creation', 'run-status', 'run-summary',
                                 'checklist', 'reminder', 'release-update'],
                        help='Email template to use')
    parser.add_argument('--subject', '-s', help='Override default subject line')
    parser.add_argument('--message', '-m', help='Custom message (for reminder template)')
    parser.add_argument('--due-date', '--due', dest='due_date', help='Due date (for reminder)')
    parser.add_argument('--milestone', default='M0', help='Milestone name (for checklist)')
    parser.add_argument('--attach', nargs='*', help='Files to attach')
    parser.add_argument('--preview', action='store_true', help='Preview email without sending')
    parser.add_argument('--html', action='store_true', help='Save HTML preview file')

    return parser
