"""Local job adverts -> career datasets (src/app/assets/careers/*.json).

Reads the team's spreadsheet (Bawsala_Local_Jobs_ESCO_*.xlsx: sheets
"الإعلانات" and "ربط المهارات"), applies the corrections listed in
CORRECTIONS (each one written down, never silent), and:

1. writes the adverts and approved skill links as CSV next to this data
   (data/careers/local_adverts_<period>.csv, ..._labels_<period>.csv), so the
   numbers can be checked without the spreadsheet;
2. adds to each role's JSON a "local_adverts" block (how many adverts, when,
   from where, labelled by how many people) and, per ESCO skill, "local_count"
   = in how many of those adverts the skill was asked for.

An advert counts once per skill. Duplicates and excluded adverts do not count.

Usage:
  python3 src/ai/careers/build_local_adverts.py <xlsx> <careers_dir> <data_dir>
"""

import csv
import json
import os
import sys

import openpyxl

ROLE_ID = {'مطوّر قواعد بيانات': 'database_developer', 'محلّل بيانات': 'data_analyst'}
NO_ESCO = 'لا تقابلها مهارة ESCO'

# Corrections agreed on 27 Nov 2026 (review of v4 in the Bousla session).
EXCLUDE_ADVERTS = {
    11: 'Field researchers and data collectors: data collection, not data analysis.',
}
RELABEL = [
    # (advert id, phrase starts with, old skill, new skill, reason)
    (1, 'statistics', 'الإحصاء', 'تطبيق تقنيات التحليل الإحصائي',
     'One ESCO skill for statistics in this sample (advert 10 uses it).'),
    (12, 'cloning/test-dev refreshes', 'إجراء النسخ الاحتياطي', NO_ESCO,
     'Cloning and test refreshes are not backups.'),
]
# Publication date not known: the sheet holds another date.
DATE_UNKNOWN = {
    2: 'The date in the sheet is the application deadline (see its note).',
}
PERIOD = '2026-06_2026-11'

# Said with the numbers, so a reader knows what was counted (28 Nov 2026).
ROLE_NOTE = {
    'data_analyst': 'Includes related titles whose adverts ask for data analysis '
                    '(monitoring and evaluation, MEAL, information management, GIS). ',
}


def main(xlsx, careers_dir, data_dir):
    wb = openpyxl.load_workbook(xlsx, data_only=True)
    ads = {}
    for r in wb['الإعلانات'].iter_rows(min_row=3, values_only=True):
        if not isinstance(r[0], (int, float)):
            continue
        aid = int(r[0])
        ads[aid] = {
            'id': aid, 'site': r[1], 'url': r[2],
            'published': '' if r[3] is None else str(r[3])[:10],
            'collected': str(r[4])[:10], 'title': r[5], 'role': r[6], 'city': r[7],
            'work_type': r[8], 'collected_with': r[12] or '',
            'duplicate': r[13] == 'نعم', 'note': r[14] or '',
        }
    labels = []
    for r in wb['ربط المهارات'].iter_rows(min_row=3, values_only=True):
        if not isinstance(r[0], (int, float)) or r[4] != 'نعم':
            continue
        labels.append({'advert': int(r[0]), 'phrase': r[1] or '', 'skill': r[2],
                       'labeller': r[3], 'note': r[6] or ''})

    applied = []
    for aid, start, old, new, why in RELABEL:
        hit = [l for l in labels if l['advert'] == aid and l['phrase'].startswith(start)
               and l['skill'] == old]
        done = [l for l in labels if l['advert'] == aid and l['phrase'].startswith(start)
                and l['skill'] == new]
        if not hit and len(done) == 1:
            applied.append(f'advert {aid}: "{start}" already {new} in the sheet')
            continue
        assert len(hit) == 1, (aid, start, len(hit))
        hit[0]['skill'] = new
        hit[0]['note'] = (hit[0]['note'] + ' | ' if hit[0]['note'] else '') + 'corrected: ' + why
        applied.append(f'advert {aid}: "{start}" {old} -> {new} ({why})')

    for aid, why in DATE_UNKNOWN.items():
        ads[aid]['note'] = (ads[aid]['note'] + ' | ' if ads[aid]['note'] else '') + \
            f'published date unknown: {why}' + (
                f' (sheet had {ads[aid]["published"]})' if ads[aid]['published'] else '')
        ads[aid]['published'] = ''
        applied.append(f'advert {aid}: published date unknown ({why})')
    # An advert with no approved skill link yet is not counted: it would add
    # to the total without adding to any skill, and understate every share.
    labelled = {l['advert'] for l in labels}
    counted = {aid for aid, a in ads.items()
               if not a['duplicate'] and aid not in EXCLUDE_ADVERTS and a['role'] in ROLE_ID
               and aid in labelled}
    labellers = sorted({l['labeller'] for l in labels if l['advert'] in counted})

    os.makedirs(data_dir, exist_ok=True)
    with open(f'{data_dir}/local_adverts_{PERIOD}.csv', 'w', newline='') as f:
        w = csv.writer(f)
        w.writerow(['id', 'site', 'url', 'published', 'collected', 'title', 'role',
                    'city', 'work_type', 'collected_with', 'counted', 'why_not_counted',
                    'note'])
        for aid in sorted(ads):
            a = ads[aid]
            why = EXCLUDE_ADVERTS.get(aid) or ('duplicate' if a['duplicate'] else '') or (
                'no approved skill links yet' if aid not in labelled else '')
            w.writerow([aid, a['site'], a['url'], a['published'], a['collected'], a['title'],
                        a['role'], a['city'], a['work_type'], a['collected_with'],
                        aid in counted, why, a['note']])
    with open(f'{data_dir}/local_adverts_labels_{PERIOD}.csv', 'w', newline='') as f:
        w = csv.writer(f)
        w.writerow(['advert', 'phrase_as_written', 'esco_skill_ar', 'labeller', 'note'])
        for l in labels:
            w.writerow([l['advert'], l['phrase'], l['skill'], l['labeller'], l['note']])

    report = []
    for role_ar, rid in ROLE_ID.items():
        path = f'{careers_dir}/{rid}.json'
        role = json.load(open(path))
        by_ar = {s['name']['ar']: s for s in role['skills']}
        role_ads = sorted(a for a in counted if ads[a]['role'] == role_ar)
        per_skill = {}
        not_in_list = []
        for l in labels:
            if l['advert'] not in role_ads or l['skill'] == NO_ESCO:
                continue
            if l['skill'] not in by_ar:
                not_in_list.append((l['advert'], l['skill']))
                continue
            per_skill.setdefault(by_ar[l['skill']]['id'], set()).add(l['advert'])
        for s in role['skills']:
            s.pop('local_count', None)
            if s['id'] in per_skill:
                s['local_count'] = len(per_skill[s['id']])
        pubs = sorted(ads[a]['published'] for a in role_ads if ads[a]['published'])
        role['local_adverts'] = {
            'total': len(role_ads),
            'published_from': pubs[0], 'published_to': pubs[-1],
            'collected': max(ads[a]['collected'] for a in role_ads),
            'sites': sorted({ads[a]['site'] for a in role_ads}),
            'labellers': len(labellers),
            'status': 'preliminary',
            'note': 'Found by the Bousla team, partly with AI search tools (column "collected_with" '
                    'in the data); each advert labelled by one person and counted once per skill. '
                    + ROLE_NOTE.get(rid, '') +
                    f'Data: data/careers/local_adverts_{PERIOD}.csv.',
        }
        with open(path, 'w') as f:
            f.write(json.dumps(role, ensure_ascii=False, indent=1) + '\n')
        report.append((rid, len(role_ads), sorted(
            ((len(v), k) for k, v in per_skill.items()), reverse=True), not_in_list))

    print('corrections:', *applied, sep='\n  ')
    print('excluded:', EXCLUDE_ADVERTS)
    print('labellers:', labellers)
    for rid, n, top, missing in report:
        print(rid, 'adverts', n)
        for c, k in top:
            print(f'   {c}/{n} {k}')
        if missing:
            print('   labels whose skill is not in this role\'s ESCO list:', missing)


if __name__ == '__main__':
    main(*sys.argv[1:4])
