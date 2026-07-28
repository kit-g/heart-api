"""
Seed content/exercise_movement.yml — the movement/substitution sidecar.

Two exercises are mutually replaceable when they share a `groups` entry. The
group is the *movement pattern*, deliberately coarser than equipment and finer
than `target` (`target: Legs` lumps calf raises with deadlifts, so it is useless
for substitution). Everything else in the record is an objective load attribute
the app filters on — never a policy flag.

  Squat (Barbell)   groups:[squat_bilateral] axial_load:high     stability:free
  Hack Squat        groups:[squat_bilateral] axial_load:moderate stability:machine
  Leg Press         groups:[squat_bilateral] axial_load:low      stability:machine

"Protect my back" is then `axial_load <= moderate` over that group, not a
hand-tagged `back_friendly` field. Keep it that way: the moment a preference
becomes a column, every new one (shoulder, knee, wrist) costs another 264-row
annotation pass.

This script derives what is mechanically derivable from name/category/target.
It is a bootstrap, not the source of truth — it never overwrites an entry that
already exists in the sidecar, so hand corrections survive re-runs. Use --force
to regenerate from scratch (discards hand edits).

Run:
  uv run python scripts/movement_seed.py            # fill in missing entries
  uv run python scripts/movement_seed.py --force    # regenerate everything
  uv run python scripts/movement_seed.py --report   # print coverage, write nothing

Then hand-review the sidecar and fold it into the master with movement_merge.py.
"""

import argparse
import os
import re
import sys
from collections import defaultdict

from ruamel.yaml import YAML

HERE = os.path.dirname(os.path.abspath(__file__))
MASTER = os.path.join(HERE, '..', 'content', 'exercise_library.yml')
SIDECAR = os.path.join(HERE, '..', 'content', 'exercise_movement.yml')

# --------------------------------------------------------------------------
# Movement groups
# --------------------------------------------------------------------------
# Matched in order against the lowercased exercise name; first hit wins, so
# specific patterns must precede general ones (wrist curl before curl, incline
# bench before bench). `guard` restricts a rule to one target when the same word
# means different things across targets ("row" is a back movement; "upright row"
# is a shoulder movement and is caught earlier).

GROUP_RULES = [
    # --- forearms before biceps: "Wrist Curl" must not match the curl rule ---
    (r'wrist',                                              None,      'forearm'),

    # --- legs ---
    (r'calf (raise|press)',                                 None,      'calf_raise'),
    (r'leg extension',                                      None,      'knee_extension'),
    (r'leg curl|glute ham raise',                           None,      'knee_flexion'),
    (r'hip abductor',                                       None,      'hip_abduction'),
    (r'hip adductor',                                       None,      'hip_adduction'),
    (r'hip thrust|single leg bridge',                       None,      'hip_extension_bridge'),
    (r'glute kickback|donkey kick|fire hydrant',            'Legs',    'glute_isolation'),
    (r'lunge|split squat|step-?up|curtsey|pistol squat',    None,      'lunge_split'),
    (r'(romanian|stiff leg|straight leg) deadlift'
     r'|good morning|pull through|kettlebell swing',        None,      'hip_hinge_stifflegged'),
    (r'deadlift|rack pull',                                 None,      'deadlift_floor'),
    (r'box jump|jump squat|high knee skips',                None,      'plyometric_lower'),
    (r'squat|leg press',                                    None,      'squat_bilateral'),

    # --- chest ---
    (r'fly|pec deck|crossover|around the world',            'Chest',   'chest_fly'),
    (r'pullover',                                           None,      'pullover'),
    (r'incline (bench press|chest press)',                  None,      'incline_press'),
    (r'decline bench press',                                None,      'decline_press'),
    (r'dip',                                                'Chest',   'chest_dip'),
    (r'bench press|chest press|floor press|push up',        'Chest',   'horizontal_press'),

    # --- back ---
    # `upright row` precedes the generic back `row` rule: it is filed under
    # target Back for the barbell variant but is a shoulder movement.
    (r'upright row',                                        None,      'upright_row'),
    (r'pulldown|pull up|chin up|muscle up',                 None,      'vertical_pull'),
    (r'row',                                                'Back',    'horizontal_row'),
    (r'back extension|superman',                            None,      'spinal_extension'),
    (r'shrug',                                              None,      'shrug'),

    # --- shoulders ---
    (r'lateral raise',                                      None,      'lateral_raise'),
    (r'front raise',                                        None,      'front_raise'),
    (r'reverse fly|face pull',                              None,      'rear_delt'),
    (r'overhead press|shoulder press|military press'
     r'|arnold press|push press|handstand push up',         None,      'vertical_press'),

    # --- arms ---
    (r'skullcrusher|triceps extension|pushdown'
     r'|triceps dip|bench dip|kickback',                    'Arms',    'elbow_extension'),
    (r'close grip',                                         'Arms',    'elbow_extension'),
    (r'curl|heart pump',                                    'Arms',    'elbow_flexion'),

    # --- core ---
    (r'plank|ab wheel',                                     None,      'core_bracing'),
    (r'crunch|sit up|v up|jackknife',                       'Core',    'trunk_flexion'),
    (r'leg raise|knee raise|knees to elbows|toes to bar'
     r'|flutter kick',                                      'Core',    'hip_flexion_hanging'),
    (r'twist|side bend|torso rotation|oblique',             'Core',    'trunk_lateral_rotation'),

    # --- olympic ---
    (r'overhead squat',                                     'Olympic', 'squat_bilateral'),
    (r'clean|snatch|jerk|press under|jump shrug|high pull',  'Olympic', 'olympic_lift'),
]

# Exercises the rules cannot reach, plus the handful that genuinely belong to
# two patterns. First group listed is the primary one.
NAME_GROUPS = {
    'Thruster (Barbell)':        ['squat_bilateral', 'vertical_press'],
    'Thruster (Kettlebell)':     ['squat_bilateral', 'vertical_press'],
    'Sumo Deadlift High Pull (Barbell)': ['deadlift_floor', 'upright_row'],
    'Ball Slams':                ['full_body_conditioning'],
    'Burpee':                    ['full_body_conditioning'],
    'Jumping Jack':              ['full_body_conditioning'],
    'Mountain Climber':          ['full_body_conditioning'],
    'Kettlebell Turkish Get Up': ['full_body_conditioning'],
    'Squat Row (Band)':          ['full_body_conditioning', 'horizontal_row'],
    'Halo':                      ['mobility'],
    'Stretching':                ['mobility'],
    'Yoga':                      ['mobility'],
}

# Groups with exactly one member are legitimate — the library simply has no
# substitute for them. Listed so movement_merge.py can warn about *unexpected*
# singletons (usually a typo) without failing on these.
KNOWN_SINGLETONS = {'knee_extension', 'hip_abduction', 'hip_adduction'}

# --------------------------------------------------------------------------
# Load attributes
# --------------------------------------------------------------------------

# Spinal compression under load. This is the field that answers "I'm protective
# of my back", so equipment overrides beat the group default: a barbell on your
# back is high regardless of pattern, a sled that puts your spine on a pad is not.
AXIAL_BY_GROUP = {
    'squat_bilateral':        'moderate',
    'lunge_split':            'moderate',
    'deadlift_floor':         'high',
    'hip_hinge_stifflegged':  'high',
    'olympic_lift':           'high',
    'horizontal_row':         'moderate',
    'shrug':                  'moderate',
    'upright_row':            'moderate',
    'vertical_press':         'moderate',
    'spinal_extension':       'moderate',
    'calf_raise':             'low',
    'hip_extension_bridge':   'low',
    'plyometric_lower':       'low',
    'full_body_conditioning': 'low',
    'front_raise':            'low',
    'lateral_raise':          'low',
    'knee_extension':         'none',
    'knee_flexion':           'none',
    'hip_abduction':          'none',
    'hip_adduction':          'none',
    'glute_isolation':        'none',
    'horizontal_press':       'none',
    'incline_press':          'none',
    'decline_press':          'none',
    'chest_fly':              'none',
    'chest_dip':              'none',
    'pullover':               'none',
    'vertical_pull':          'none',   # hanging is spinal traction, not compression
    'rear_delt':              'none',
    'elbow_flexion':          'none',
    'elbow_extension':        'none',
    'forearm':                'none',
    'core_bracing':           'none',
    'trunk_flexion':          'none',
    'hip_flexion_hanging':    'none',
    'trunk_lateral_rotation': 'low',
    'cardio_steady':          'none',
    'mobility':               'none',
}

# Checked before the group default. Order matters.
AXIAL_OVERRIDES = [
    # Bar on the back or held at the trunk under real load.
    (r'^squat \(barbell\)|^front squat|^box squat|^zercher|^overhead squat', 'high'),
    (r'^hack squat \(barbell\)',                        'high'),   # bar behind the legs, spine loaded
    (r'^lunge \(barbell\)|^step-up \(barbell\)|^bulgarian split squat', 'high'),
    (r'^standing calf raise \(barbell\)',               'moderate'),
    (r'^good morning',                                  'high'),
    (r'^bent over row \(barbell\)|^bent over row - underhand|^pendlay row', 'high'),
    (r'^shrug \(barbell\)',                             'high'),
    (r'^strict military press|^push press|^thruster \(barbell\)', 'high'),
    # Spine supported by a pad or the load path is off the spine.
    (r'^hack squat$|^squat \(machine\)|^squat \(smith machine\)', 'moderate'),
    (r'leg press',                                      'low'),
    (r'^trap bar deadlift',                             'moderate'),
    (r'^kettlebell swing',                              'moderate'),
    (r'^seated .*row|^iso-lateral row|^inverted row',   'low'),
    (r'^t bar row',                                     'moderate'),
    (r'^seated overhead press|^shoulder press|^overhead press \(machine\)', 'low'),
    (r'^back extension \(machine\)',                    'low'),
    (r'^cable pull through',                            'low'),
    # Unloaded bodyweight versions carry no external spinal load.
    (r'^squat \(bodyweight\)|^lunge \(bodyweight\)|^step-up \(bodyweight\)', 'none'),
    (r'^hip thrust \(bodyweight\)|^single leg bridge',  'none'),
    (r'^standing calf raise \(bodyweight\)|^seated calf raise', 'none'),
    (r'\(band\)',                                       'low'),
]

FIXED_PATH = r'\(machine\)|\(smith machine\)|\(plate loaded\)|leg press|pec deck|^hack squat$|machine\)$'
SUPPORTED = (r'\(cable\)|cable |seated |lying |incline |preacher|bench |decline |'
             r'concentration|chest fly|pulldown|pec deck|assisted')
UNILATERAL = (r'single arm|one arm|single leg|bulgarian|pistol|concentration|split squat|'
              r'curtsey|step-?up|lunge|side plank|side bend|oblique crunch|cross body|'
              r'donkey kick|fire hydrant|iso-lateral|kickback|bicycle crunch|halo|'
              r'turkish get up|flutter kick')

HIGH_IMPACT = (r'box jump|jump squat|jumping jack|jump rope|burpee|^running|high knee|'
               r'kipping|ball slams|mountain climber|skating')
LOW_IMPACT = r'^walking|^hiking|^climbing|^aerobics|^battle ropes|plyometric|^snowboarding|^skiing'

HIGH_SKILL = (r'snatch|clean|jerk|press under|muscle up|handstand push up|pistol squat|'
              r'turkish get up|overhead squat|kipping|zercher')
MODERATE_SKILL = (r'\(barbell\)|deadlift|bulgarian|glute ham raise|ab wheel|deficit|'
                  r'trap bar|dip$|pull up|chin up|toes to bar|thruster|kettlebell swing|'
                  r'good morning|push press')


def match(patterns: str, name: str) -> bool:
    return re.search(patterns, name) is not None


def groups_for(name: str, target: str) -> list[str]:
    if name in NAME_GROUPS:
        return NAME_GROUPS[name]
    if target == 'Cardio':
        return ['cardio_steady']
    lowered = name.lower()
    for pattern, guard, group in GROUP_RULES:
        if guard and target != guard:
            continue
        if re.search(pattern, lowered):
            return [group]
    return []


def axial_load_for(name: str, groups: list[str]) -> str:
    lowered = name.lower()
    for pattern, value in AXIAL_OVERRIDES:
        if re.search(pattern, lowered):
            return value
    return AXIAL_BY_GROUP.get(groups[0], 'none') if groups else 'none'


def stability_for(name: str, category: str) -> str:
    lowered = name.lower()
    if match(FIXED_PATH, lowered) or category == 'Machine' and 'cable' not in lowered:
        return 'machine'
    if match(SUPPORTED, lowered):
        return 'supported'
    return 'free'


def annotate(name: str, exercise: dict) -> dict | None:
    groups = groups_for(name, exercise['target'])
    if not groups:
        return None
    lowered = name.lower()
    return {
        'groups': groups,
        'axial_load': axial_load_for(name, groups),
        'stability': stability_for(name, exercise['category']),
        'unilateral': match(UNILATERAL, lowered),
        'impact': 'high' if match(HIGH_IMPACT, lowered)
                  else 'low' if match(LOW_IMPACT, lowered) else 'none',
        'skill': 'high' if match(HIGH_SKILL, lowered)
                 else 'moderate' if match(MODERATE_SKILL, lowered) else 'low',
    }


def build_yaml() -> YAML:
    yaml = YAML()
    yaml.preserve_quotes = True
    yaml.width = 4096
    yaml.indent(mapping=2, sequence=4, offset=2)
    return yaml


def report(annotations: dict, exercises: dict) -> None:
    by_group = defaultdict(list)
    for name, record in annotations.items():
        for group in record['groups']:
            by_group[group].append(name)

    ungrouped = [n for n in exercises if n not in annotations]
    print(f'{len(exercises)} exercises -> {len(annotations)} annotated, '
          f'{len(by_group)} groups, {len(ungrouped)} ungrouped')

    for group in sorted(by_group, key=lambda g: (-len(by_group[g]), g)):
        members = by_group[group]
        flag = '  <- SINGLETON' if len(members) == 1 and group not in KNOWN_SINGLETONS else ''
        print(f'  {group:24} {len(members):3}{flag}')

    if ungrouped:
        print('\nungrouped (no substitutes offered):')
        for name in ungrouped:
            print(f'  {name}')


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--force', action='store_true',
                        help='regenerate every entry, discarding hand edits')
    parser.add_argument('--report', action='store_true',
                        help='print coverage without writing the sidecar')
    args = parser.parse_args()

    yaml = build_yaml()
    with open(MASTER) as f:
        exercises = yaml.load(f)['exercises']

    existing = {}
    if os.path.exists(SIDECAR) and not args.force:
        with open(SIDECAR) as f:
            existing = yaml.load(f) or {}

    annotations, kept = {}, 0
    for name, exercise in exercises.items():
        if name in existing:
            annotations[name] = existing[name]
            kept += 1
            continue
        record = annotate(name, exercise)
        if record is not None:
            annotations[name] = record

    stale = [n for n in existing if n not in exercises]

    report(annotations, exercises)
    if kept:
        print(f'\n{kept} existing entries preserved (--force to regenerate)')
    if stale:
        print(f'\nWARNING: {len(stale)} sidecar entries no longer in the library: '
              f'{", ".join(stale)}')

    if args.report:
        return 0

    with open(SIDECAR, 'w') as f:
        f.write('# Movement patterns and load attributes, keyed by exercise name.\n'
                '# Exercises sharing a `groups` entry are mutually replaceable.\n'
                '# Seeded by scripts/movement_seed.py; hand edits here are preserved.\n'
                '# Fold into content/exercise_library.yml with scripts/movement_merge.py.\n')
        yaml.dump(annotations, f)
    print(f'\nwrote {SIDECAR}')
    return 0


if __name__ == '__main__':
    sys.exit(main())
