"""Installation guide for non-technical staff (Daily Expense Tracker, BCR).

Usage (from the repo root):
    python tool/guides/make_install_guide.py --client "InsideOut Casa" \
        --apk dist/insideout-casa/DailyExpenseTracker-insideout-casa-1.0.3-build4.apk \
        --out dist/insideout-casa/How-to-install-Daily-Expense-Tracker.pdf

A5 portrait, large text, drawn phone screens that show which button to tap.
"""
import argparse
import os

from reportlab.lib import colors
from reportlab.lib.enums import TA_CENTER
from reportlab.lib.pagesizes import A5
from reportlab.lib.styles import ParagraphStyle
from reportlab.lib.units import mm
from reportlab.pdfbase import pdfmetrics
from reportlab.lib.fonts import addMapping
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import (Flowable, Image, KeepTogether, PageBreak,
                                Paragraph, SimpleDocTemplate, Spacer, Table,
                                TableStyle)

BLUE = colors.HexColor('#1565C0')
BLUE_DARK = colors.HexColor('#0D47A1')
BLUE_LIGHT = colors.HexColor('#E3F2FD')
AMBER_BG = colors.HexColor('#FFF4E5')
AMBER = colors.HexColor('#8A4B00')
RED = colors.HexColor('#D32F2F')
GREEN = colors.HexColor('#2E7D32')
TEXT = colors.HexColor('#1A1C1E')
MUTED = colors.HexColor('#4A5560')
SCREEN_BG = colors.HexColor('#F6F8FB')

FONT_DIRS = ['C:/Windows/Fonts', '/System/Library/Fonts/Supplemental', '/usr/share/fonts/truetype/msttcorefonts']


def register_fonts():
    for d in FONT_DIRS:
        reg, bold = os.path.join(d, 'arial.ttf'), os.path.join(d, 'arialbd.ttf')
        if os.path.exists(reg) and os.path.exists(bold):
            pdfmetrics.registerFont(TTFont('Body', reg))
            pdfmetrics.registerFont(TTFont('Body-Bold', bold))
            # Map <b>/<i> in paragraphs to the bold face.
            for b_, i_, name in [(0, 0, 'Body'), (1, 0, 'Body-Bold'), (0, 1, 'Body'), (1, 1, 'Body-Bold')]:
                addMapping('Body', b_, i_, name)
            return 'Body', 'Body-Bold'
    return 'Helvetica', 'Helvetica-Bold'


F, FB = register_fonts()

S = {
    'title': ParagraphStyle('title', fontName=FB, fontSize=20, leading=24, textColor=colors.white),
    'subtitle': ParagraphStyle('subtitle', fontName=F, fontSize=11, leading=14, textColor=colors.white),
    'h': ParagraphStyle('h', fontName=FB, fontSize=15, leading=19, textColor=BLUE_DARK, spaceBefore=4, spaceAfter=4),
    'step': ParagraphStyle('step', fontName=FB, fontSize=14, leading=18, textColor=TEXT, spaceAfter=3),
    'num': ParagraphStyle('num', fontName=FB, fontSize=14, leading=16, textColor=colors.white, alignment=TA_CENTER),
    'body': ParagraphStyle('body', fontName=F, fontSize=11.5, leading=15.5, textColor=TEXT, spaceAfter=4),
    'small': ParagraphStyle('small', fontName=F, fontSize=9.5, leading=12.5, textColor=MUTED),
    'box': ParagraphStyle('box', fontName=F, fontSize=11, leading=15, textColor=TEXT),
    'center': ParagraphStyle('center', fontName=F, fontSize=9, leading=12, textColor=MUTED, alignment=TA_CENTER),
}


def P(text, style='body'):
    return Paragraph(text, S[style])


class PhoneScreen(Flowable):
    """A simple drawn phone showing a message and the button to tap."""

    def __init__(self, title, lines, buttons, tap, width=44 * mm, height=62 * mm, note=None):
        super().__init__()
        self.title, self.lines, self.buttons, self.tap = title, lines, buttons, tap
        self.width, self.height, self.note = width, height, note

    def wrap(self, aw, ah):
        return self.width, self.height

    def draw(self):
        c = self.canv
        w, h = self.width, self.height
        # Body of the phone.
        c.setFillColor(colors.HexColor('#263238'))
        c.roundRect(0, 0, w, h, 6 * mm, fill=1, stroke=0)
        sx, sy, sw, sh = 2.5 * mm, 6 * mm, w - 5 * mm, h - 11 * mm
        c.setFillColor(SCREEN_BG)
        c.roundRect(sx, sy, sw, sh, 3 * mm, fill=1, stroke=0)
        # Title bar.
        c.setFillColor(BLUE)
        c.roundRect(sx, sy + sh - 9 * mm, sw, 9 * mm, 3 * mm, fill=1, stroke=0)
        c.rect(sx, sy + sh - 9 * mm, sw, 4 * mm, fill=1, stroke=0)
        c.setFillColor(colors.white)
        c.setFont(FB, 8.5)
        c.drawString(sx + 3 * mm, sy + sh - 6 * mm, self.title)
        # Message lines.
        y = sy + sh - 15 * mm
        for i, line in enumerate(self.lines):
            c.setFillColor(TEXT if i else TEXT)
            c.setFont(FB if line.startswith('**') else F, 7.5)
            c.drawString(sx + 3 * mm, y, line.strip('*'))
            y -= 4.2 * mm
        # Buttons (bottom up).
        by = sy + 4 * mm
        for label in reversed(self.buttons):
            hit = label == self.tap
            bw = sw - 8 * mm
            bx = sx + 4 * mm
            c.setFillColor(BLUE if hit else colors.white)
            c.setStrokeColor(BLUE)
            c.setLineWidth(1)
            c.roundRect(bx, by, bw, 7.5 * mm, 3.7 * mm, fill=1, stroke=1)
            c.setFillColor(colors.white if hit else BLUE)
            c.setFont(FB, 8.5)
            c.drawCentredString(bx + bw / 2, by + 2.5 * mm, label)
            if hit:
                # Red ring + "TAP" marker.
                c.setStrokeColor(RED)
                c.setLineWidth(2)
                c.roundRect(bx - 1.5 * mm, by - 1.5 * mm, bw + 3 * mm, 10.5 * mm, 5 * mm, fill=0, stroke=1)
                c.setFillColor(RED)
                c.circle(bx + bw + 1 * mm, by + 9.5 * mm, 3.2 * mm, fill=1, stroke=0)
                c.setFillColor(colors.white)
                c.setFont(FB, 6.5)
                c.drawCentredString(bx + bw + 1 * mm, by + 8.6 * mm, 'TAP')
            by += 9.5 * mm
        if self.note:
            c.setFillColor(colors.HexColor('#CFD8DC'))
            c.setFont(F, 6.5)
            c.drawCentredString(w / 2, 1.8 * mm, self.note)


def step(number, title, body_paras, phone=None):
    num = Table([[Paragraph(str(number), S['num'])]], colWidths=[9 * mm], rowHeights=[9 * mm])
    num.setStyle(TableStyle([
        ('BACKGROUND', (0, 0), (-1, -1), BLUE),
        ('ALIGN', (0, 0), (-1, -1), 'CENTER'), ('VALIGN', (0, 0), (-1, -1), 'MIDDLE'),
        ('ROUNDEDCORNERS', [4.5 * mm] * 4),
        ('LEFTPADDING', (0, 0), (-1, -1), 0), ('RIGHTPADDING', (0, 0), (-1, -1), 0),
        ('TOPPADDING', (0, 0), (-1, -1), 0), ('BOTTOMPADDING', (0, 0), (-1, -1), 1),
    ]))
    head = Table([[num, P(title, 'step')]], colWidths=[11 * mm, None])
    head.setStyle(TableStyle([('VALIGN', (0, 0), (-1, -1), 'MIDDLE'),
                              ('LEFTPADDING', (0, 0), (-1, -1), 0)]))
    text = [P(t) for t in body_paras]
    if phone is None:
        return KeepTogether([head, Spacer(1, 2 * mm)] + text + [Spacer(1, 5 * mm)])
    row = Table([[text, phone]], colWidths=[None, 50 * mm])
    row.setStyle(TableStyle([
        ('VALIGN', (0, 0), (-1, -1), 'TOP'), ('ALIGN', (1, 0), (1, 0), 'RIGHT'),
        ('LEFTPADDING', (0, 0), (-1, -1), 0), ('RIGHTPADDING', (0, 0), (-1, -1), 0),
    ]))
    return KeepTogether([head, Spacer(1, 1.5 * mm), row, Spacer(1, 4 * mm)])


def box(paras, bg=BLUE_LIGHT, border=BLUE):
    t = Table([[[P(p, 'box') for p in paras]]], colWidths=[None])
    t.setStyle(TableStyle([
        ('BACKGROUND', (0, 0), (-1, -1), bg),
        ('BOX', (0, 0), (-1, -1), 0.8, border),
        ('ROUNDEDCORNERS', [3 * mm] * 4),
        ('LEFTPADDING', (0, 0), (-1, -1), 4 * mm), ('RIGHTPADDING', (0, 0), (-1, -1), 4 * mm),
        ('TOPPADDING', (0, 0), (-1, -1), 3 * mm), ('BOTTOMPADDING', (0, 0), (-1, -1), 3 * mm),
    ]))
    return t


def build(client, apk, out, contact):
    size_mb = os.path.getsize(apk) / (1024 * 1024)
    apk_name = os.path.basename(apk)
    version = apk_name.split('-')[-2] if apk_name.count('-') >= 3 else ''
    here = os.path.dirname(os.path.abspath(__file__))
    icon = os.path.join(here, '..', 'icon', 'icon_1024.png')

    def on_page(c, doc):
        c.saveState()
        c.setFont(F, 7.5)
        c.setFillColor(MUTED)
        c.drawCentredString(A5[0] / 2, 7 * mm,
                            f'Daily Expense Tracker · for {client} · Crafted by BCR · page {doc.page}')
        c.restoreState()

    doc = SimpleDocTemplate(out, pagesize=A5, leftMargin=11 * mm, rightMargin=11 * mm,
                            topMargin=10 * mm, bottomMargin=13 * mm,
                            title='How to install Daily Expense Tracker',
                            author='BCR (BibinCutRiver)', subject=f'Installation guide for {client} staff')
    story = []

    # ---------- Header ----------
    head_left = [P('How to install<br/>Daily Expense Tracker', 'title'), Spacer(1, 2 * mm),
                 P(f'For {client} staff · Android phones · about 5 minutes', 'subtitle')]
    head = Table([[Image(icon, 20 * mm, 20 * mm) if os.path.exists(icon) else '', head_left]],
                 colWidths=[24 * mm, None])
    head.setStyle(TableStyle([
        ('BACKGROUND', (0, 0), (-1, -1), BLUE), ('VALIGN', (0, 0), (-1, -1), 'MIDDLE'),
        ('ROUNDEDCORNERS', [4 * mm] * 4),
        ('LEFTPADDING', (0, 0), (-1, -1), 4 * mm), ('TOPPADDING', (0, 0), (-1, -1), 4 * mm),
        ('BOTTOMPADDING', (0, 0), (-1, -1), 4 * mm),
    ]))
    story += [head, Spacer(1, 5 * mm)]

    story += [P('Before you start', 'h'),
              box([
                  '<b>1. Android phone.</b> This guide is for Android (Samsung, Xiaomi, Oppo, Huawei and others). '
                  'iPhone is not available yet.',
                  '<b>2. Screen lock on.</b> Your phone must have a PIN, pattern, password or fingerprint. '
                  'Check: <b>Settings → Lock screen</b> (or <b>Security</b>).',
                  '<b>3. Right file.</b> Install only the file sent to you by your office:<br/>'
                  f'<font size="9.5"><b>{apk_name}</b></font><br/>'
                  f'Size about <b>{size_mb:.0f} MB</b>{f" · version {version}" if version else ""}.',
              ]),
              Spacer(1, 4 * mm),
              box([
                  '<b>Is this safe?</b> Yes. This app does <b>not use the internet</b>. It never asks for '
                  'passwords, bank details or personal information, and does not read your messages, '
                  'photos or contacts. Your expenses stay locked on your own phone.',
              ], bg=AMBER_BG, border=AMBER),
              PageBreak()]

    # ---------- Steps ----------
    story.append(step(
        1, 'Download the file',
        ['Open the WhatsApp (or email) message from your office with the file. '
         'Tap the file and <b>wait until it finishes downloading</b> (the circle stops turning).'],
        PhoneScreen('WhatsApp', ['**Office', 'DailyExpense...apk', f'{size_mb:.0f} MB · APK'],
                    ['Open file'], 'Open file', note='Tap the file once it has downloaded'),
    ))
    story.append(step(
        2, 'Allow the install (only the first time)',
        ['Your phone shows a message like <i>"For your security, your phone is not allowed to install '
         'unknown apps from this source"</i>. This is normal for apps not from Play Store.',
         'Tap <b>Settings</b>, switch <b>ON</b> “Allow from this source”, then press the '
         '<b>back arrow</b> once.'],
        PhoneScreen('Install blocked', ['For your security, your', 'phone is not allowed to',
                                        'install unknown apps', 'from this source.'],
                    ['Settings', 'Cancel'], 'Settings', note='Then: switch ON → Back'),
    ))
    story.append(step(
        3, 'Install',
        ['Tap <b>Install</b> and wait a few seconds.',
         'If Google Play Protect shows a warning (for example <i>"Unsafe app blocked"</i> or '
         '<i>"App scan recommended"</i>): tap <b>More details</b> and then <b>Install anyway</b>, '
         'or tap <b>Scan app</b> and then <b>Install</b>. It appears only because the app is a private '
         'company app and not on Play Store.'],
        PhoneScreen('Daily Expense Tracker', ['**Do you want to install', '**this app?'],
                    ['Install', 'Cancel'], 'Install'),
    ))
    story.append(step(
        4, 'Open and unlock',
        ['Tap <b>Open</b>. The app asks for your <b>fingerprint, face or phone PIN</b> — '
         'the same one you use to unlock your phone.',
         f'You will see <b>Today · AED 0.00</b> and <b>{client}</b> at the top. '
         '<b>That’s it — the app is ready.</b> No code or registration is needed.'],
        PhoneScreen('Daily Expense Tracker', ['**Today', '**AED 0.00', '0 entries', '',
                                              'No expenses yet'],
                    ['+ Add Expense'], None, note='Ready to use'),
    ))
    story.append(P('<b>Tip:</b> after installing you can switch “Allow from this source” off again '
                   '(Settings → Apps → WhatsApp → Install unknown apps).', 'small'))
    story.append(PageBreak())

    # ---------- Daily use ----------
    story += [P('Recording an expense', 'h'),
              box([
                  '1. Tap <b>Add Expense</b>.',
                  '2. <b>Description</b>: choose what it was for (Petrol, Food, Salik…).',
                  '3. <b>Amount</b>: type the AED amount, e.g. <b>25</b> or <b>25.50</b>.',
                  '4. <b>Remarks</b> (optional): any detail, e.g. vehicle number. Required for “Other”.',
                  '5. Tap <b>Save expense</b>. Date and time are added automatically.',
              ]),
              Spacer(1, 3 * mm),
              P('To change or delete an expense, tap it in the list. '
                '<b>Reports</b> (bottom of the screen) shows daily, weekly and monthly totals.'),
              Spacer(1, 3 * mm),
              P('Important rules', 'h'),
              box([
                  '<b>Never uninstall the app.</b> Uninstalling or “Clear data” deletes your expenses '
                  'permanently.',
                  '<b>Updates:</b> when the office sends a new file, just install it the same way — '
                  'your expenses stay.',
                  '<b>Back up once a month:</b> Settings → <b>Create backup</b> → choose a password '
                  '(8 or more characters) → save it to Google Drive or send it to yourself. '
                  'Remember the password!',
                  '<b>New phone?</b> Install the app on the new phone, then tap '
                  '<b>“Restore a backup”</b> and choose your backup file.',
              ], bg=AMBER_BG, border=AMBER),
              PageBreak()]

    # ---------- Problems ----------
    story.append(P('If something goes wrong', 'h'))
    rows = [
        ('I can’t find the downloaded file',
         'Go back to the WhatsApp message and tap the file again. Or open the <b>Files</b> app '
         '(<b>My Files</b> on Samsung) → <b>Downloads</b> or <b>Documents</b>.'),
        ('“There was a problem parsing the package”',
         'The download did not finish. Delete it and download the file again on Wi-Fi.'),
        ('“App not installed”',
         'Make sure there is free storage (at least 200 MB). Restart the phone and try again.'),
        ('App says “Set up a screen lock first”',
         'Add a PIN, pattern or password in Settings → Lock screen, then tap <b>Check again</b>.'),
        ('App says “Too many attempts”',
         'Wait a minute, unlock the phone with its PIN, then tap <b>Unlock</b> in the app.'),
        ('Lost or forgot the backup password', 'The backup cannot be opened by anyone. Make a new backup.'),
    ]
    t = Table([[P(f'<b>{a}</b>', 'box'), P(b, 'box')] for a, b in rows], colWidths=[44 * mm, None])
    t.setStyle(TableStyle([
        ('VALIGN', (0, 0), (-1, -1), 'TOP'),
        ('LINEBELOW', (0, 0), (-1, -2), 0.5, colors.HexColor('#DCE3EC')),
        ('TOPPADDING', (0, 0), (-1, -1), 2.5 * mm), ('BOTTOMPADDING', (0, 0), (-1, -1), 2.5 * mm),
        ('LEFTPADDING', (0, 0), (-1, -1), 1.5 * mm),
    ]))
    story += [t, Spacer(1, 6 * mm)]
    story.append(box([
        '<b>Need help?</b> Contact your office:',
        contact if contact else 'Name: ______________________<br/><br/>Phone: _____________________',
    ]))
    story.append(Spacer(1, 6 * mm))
    story.append(P(f'Daily Expense Tracker {version} · licensed to {client}<br/>Crafted by BCR (BibinCutRiver)',
                   'center'))

    doc.build(story, onFirstPage=on_page, onLaterPages=on_page)


if __name__ == '__main__':
    ap = argparse.ArgumentParser()
    ap.add_argument('--client', required=True)
    ap.add_argument('--apk', required=True)
    ap.add_argument('--out', required=True)
    ap.add_argument('--contact', default='', help='Office contact line, e.g. "Ahmed · 050 123 4567"')
    a = ap.parse_args()
    build(a.client, a.apk, a.out, a.contact)
    print('Wrote', a.out)
