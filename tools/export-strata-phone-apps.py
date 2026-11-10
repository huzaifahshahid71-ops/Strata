"""Export app names/IDs, registered URL schemes and icons from a paired iPhone for Strata's opt-in picker. No app data is read."""
import asyncio,json,argparse
from pathlib import Path
from pymobiledevice3.lockdown import create_using_usbmux
from pymobiledevice3.services.installation_proxy import InstallationProxyService
from pymobiledevice3.services.house_arrest import HouseArrestService
from pymobiledevice3.services.springboard import SpringBoardServicesService
async def run(args):
 l=await create_using_usbmux(serial=args.udid)
 async with InstallationProxyService(l) as service:
  values=await service.browse(options={'ApplicationType':'Any'},attributes=['CFBundleIdentifier','CFBundleDisplayName','CFBundleName','ApplicationType','CFBundleURLTypes'])
 seen=set();apps=[]
 for value in values:
  identifier=value.get('CFBundleIdentifier');name=value.get('CFBundleDisplayName') or value.get('CFBundleName')
  if not isinstance(identifier,str) or not isinstance(name,str) or not name or identifier==args.strata_id or identifier in seen:continue
  if len(identifier)>255 or len(name)>120:continue
  schemes=[]
  for urltype in value.get('CFBundleURLTypes') or []:
   for scheme in (urltype.get('CFBundleURLSchemes') or []) if isinstance(urltype,dict) else []:
    if isinstance(scheme,str) and 0<len(scheme)<=64 and scheme not in schemes:schemes.append(scheme)
  seen.add(identifier);apps.append({'id':identifier,'name':name,'schemes':schemes[:12]})
 apps.sort(key=lambda a:a['name'].casefold())
 data=json.dumps(apps,ensure_ascii=False,indent=2).encode()
 if not apps:raise RuntimeError('No app names returned by paired device')
 args.output.parent.mkdir(parents=True,exist_ok=True);args.output.write_bytes(data)
 icons={}
 if args.icons:
  async with SpringBoardServicesService(l) as springboard:
   for app in apps:
    try:
     png=await springboard.get_icon_pngdata(app['id'])
     if png and png[:8]==b'\x89PNG\r\n\x1a\n' and len(png)<=2_000_000:icons[app['id']]=png
    except Exception:pass
  folder=args.output.parent/'PhoneAppIcons';folder.mkdir(parents=True,exist_ok=True)
  for identifier,png in icons.items():(folder/(identifier+'.png')).write_bytes(png)
 if args.copy_to_strata:
  async with await HouseArrestService.create(l,args.strata_id) as service:
   await service.makedirs('/Documents/Strata3')
   if icons:
    await service.makedirs('/Documents/Strata3/PhoneAppIcons')
    for identifier,png in icons.items():await service.set_file_contents('/Documents/Strata3/PhoneAppIcons/'+identifier+'.png',png)
   await service.set_file_contents('/Documents/Strata3/PhoneAppsCatalog.json',data)
   assert await service.get_file_contents('/Documents/Strata3/PhoneAppsCatalog.json')==data
 print(json.dumps({'apps':len(apps),'withSchemes':sum(1 for a in apps if a['schemes']),'icons':len(icons),'output':str(args.output),'copiedToStrata':args.copy_to_strata}))
 await l.close()
if __name__=='__main__':
 parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--udid',required=True);parser.add_argument('--strata-id',required=True);parser.add_argument('--output',type=Path,required=True);parser.add_argument('--copy-to-strata',action='store_true');parser.add_argument('--icons',action='store_true',help='also export app icons (SpringBoard services)');args=parser.parse_args()
 asyncio.run(asyncio.wait_for(run(args),600))
