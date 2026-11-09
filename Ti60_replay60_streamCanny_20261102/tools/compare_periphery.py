"""Compare effective LPF instance parameters, ignoring formatting and timestamps."""
import sys
import xml.etree.ElementTree as ET

def parameters(path):
    root = ET.parse(path).getroot()
    ns = {'e': root.tag.split('}')[0].lstrip('{')}
    result = {}
    for instance in root.findall('e:instance', ns):
        for parameter in instance.findall('e:parameter', ns):
            result[(instance.get('name') or instance.get('id'), parameter.get('name'))] = parameter.get('value')
    return result

old, new = map(parameters, sys.argv[1:3])
print('Instance parameters:', len(old), len(new))
differences = [(key, old.get(key), new.get(key)) for key in sorted(old.keys() | new.keys()) if old.get(key) != new.get(key)]
for key, before, after in differences:
    print(key, repr(before), '->', repr(after))
print('Differences:', len(differences))
