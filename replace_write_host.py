import os
import re
import codecs

root_dir = r"d:\xy2401\codePublic\powershell2401\functions"

for root, _, files in os.walk(root_dir):
    for filename in files:
        if filename.endswith('.ps1') or filename.endswith('.psm1'):
            filepath = os.path.join(root, filename)
            try:
                with open(filepath, 'rb') as f:
                    content = f.read()
            except: continue
            
            # Detect UTF-8 BOM
            if content.startswith(codecs.BOM_UTF8):
                try: text = content[3:].decode('utf-8')
                except: continue
                bom = codecs.BOM_UTF8
            elif content.startswith(codecs.BOM_UTF16_LE):
                try: text = content[2:].decode('utf-16-le')
                except: continue
                bom = codecs.BOM_UTF16_LE
            else:
                try: text = content.decode('utf-8')
                except: 
                    # fallback to System default ANSI / GBK in case user had un-encodeable gb2312
                    try: text = content.decode('mbcs')
                    except: continue
                bom = b''
            
            new_text = re.sub(r'(?i)\bWrite-Host\b', 'Write-LogMessage -NoPrefix', text)
            
            if text != new_text:
                with open(filepath, 'wb') as f:
                    if bom == codecs.BOM_UTF16_LE:
                        f.write(bom + new_text.encode('utf-16-le'))
                    else:
                        f.write(bom + new_text.encode('utf-8'))
                print("Updated", filepath)
