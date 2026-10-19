"""Run real TCP static/hybrid servers and test idle console shutdown on Windows."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import signal
import socket
import subprocess
import sys
import time
import urllib.request

assert sys.platform=='win32'
root=Path(__file__).resolve().parents[2]
moon=Path(sys.argv[1]).resolve()
fixture=Path(sys.argv[2]).resolve()
clingy=Path(sys.argv[3]).resolve()
ballad=Path(sys.argv[4]).resolve()
env=dict(os.environ,METEORITE_TEST_ROOT=root.as_posix(),CLINGY_TEST_ROOT=clingy.as_posix(),BALLAD_TEST_ROOT=ballad.as_posix())
wrapper=root/'tests/windows/cli.lua'
def run(*args,timeout=300):
    subprocess.run([str(moon),'-C',str(fixture),'exec','--',*map(str,args)],env=env,check=True,timeout=timeout)
def cli(*args): run('lua',wrapper,*args)
def port():
    with socket.socket() as listener:
        listener.bind(('127.0.0.1',0)); return listener.getsockname()[1]
def request(url,expected,seconds=30,process=None):
    deadline=time.monotonic()+seconds
    last=None
    while time.monotonic()<deadline:
        if process is not None and process.poll() is not None:
            raise AssertionError(("process exited before readiness",process.returncode,last))
        try:
            with urllib.request.urlopen(url,timeout=1) as response:
                data=response.read(); assert response.status==200
                if expected in data: return
                last=(url,data)
                time.sleep(.05)
        except (OSError,TimeoutError) as error:
            last=error; time.sleep(.05)
    raise AssertionError((url,last))

# Scaffolding must work from the public command without mkdir/find/Bash.
scaffold=fixture/'scaffold space'
cli('init',scaffold,'--name','windows-scaffold','--no-sync','--static')
assert (scaffold/'src/main.lua').exists()
assert (scaffold/'Watch_supervisor.lua').exists()

archive=fixture/'lua-5.4.7.tar.gz'
with urllib.request.urlopen('https://www.lua.org/ftp/lua-5.4.7.tar.gz',timeout=60) as response:
    archive.write_bytes(response.read())
expected=(root/'tests/windows/lua-source.sha256').read_text().strip()
assert hashlib.sha256(archive.read_bytes()).hexdigest()==expected
lua_root=fixture/'target-lua'
cli('build-lua',archive,lua_root,'x86_64-windows-gnu','ReleaseSafe')
assert (lua_root/'bin/lua.exe').exists()

(fixture/'src').mkdir(exist_ok=True)
(fixture/'zig').mkdir(exist_ok=True)
(fixture/'zig/handlers.zig').write_text('pub fn health(ctx: anytype) !void { try ctx.text(200,"native windows"); }\n')
for mode in ('release-static','hybrid_dev'):
    for backend in ('std_http','fast_http'):
        number=port()
        handler='"handlers.health"' if mode=='release-static' else 'function(c) return c:text("native windows") end'
        (fixture/'src/main.lua').write_text('local m=require("meteorite")\nlocal app=m.app({name="windows",port='+str(number)+'})\napp:get("/health",'+handler+')\nreturn app\n')
        binary=fixture/('dist/'+mode+'-'+backend+'.exe')
        options=['zig','build','--build-file',root/'build.zig','install-server',
                 '-Dproject-root='+fixture.as_posix(),'-Dmeteorite-cli='+wrapper.as_posix(),
                 '-Dgraph-input=src/main.lua','-Dgraph-output=.meteorite/graph/'+mode+'-'+backend,
                 '-Dmode='+mode,'-Dbackend='+backend,'-Dlua-root='+lua_root.as_posix()]
        if mode=='hybrid_dev': options+=['-Ddev-events='+str(fixture/'events.log')]
        run(*options,'--',binary)
        # Relocation: execute a copy from another directory, outside the source.
        relocated=fixture/('relocated '+mode+' '+backend)
        relocated.mkdir(exist_ok=True)
        target=relocated/'server.exe'; shutil.copy2(binary,target)
        if mode=='hybrid_dev':
            # Development handlers are runtime source assets, not embedded code.
            # Relocate the declared closure, including the generated Lua chunks.
            shutil.copytree(fixture/'.meteorite/lua',relocated/'.meteorite/lua',dirs_exist_ok=True)
        output=open(relocated/'server.log','wb')
        process=subprocess.Popen([str(target)],cwd=relocated,stdout=output,stderr=subprocess.STDOUT,
                                 creationflags=subprocess.CREATE_NEW_PROCESS_GROUP,env=env)
        try:
            request('http://127.0.0.1:'+str(number)+'/health',b'native windows')
            if mode=='hybrid_dev':
                assert any(json.loads(line).get('kind')=='request' for line in (fixture/'events.log').read_text().splitlines())
            # Idle means no request is available to wake a blocking accept.
            time.sleep(.1)
            started=time.monotonic()
            process.send_signal(signal.CTRL_BREAK_EVENT)
            process.wait(timeout=5)
            assert time.monotonic()-started<5
            assert process.returncode==0,(mode,backend,process.returncode)
            print('PASS:',mode,backend,'HTTP, relocated binary and idle shutdown',flush=True)
        except BaseException:
            output.flush()
            print((relocated/'server.log').read_text(errors='replace'),flush=True)
            raise
        finally:
            if process.poll() is None: process.kill(); process.wait(timeout=10)
            output.close()

# Complete direct dev lifecycle, including an inline Lua edit and retirement.
number=port()
entry=fixture/'src/main.lua'
def application(message):
    return 'local m=require("meteorite")\nlocal app=m.app({name="windows-dev",port='+str(number)+'})\napp:get("/health",function(c) return c:text("'+message+'") end)\nreturn app\n'
entry.write_text(application('before edit'))
devlog=fixture/'dev-session.log'
with open(devlog,'wb') as output:
    session=subprocess.Popen([str(moon),'-C',str(fixture),'exec','--','lua',str(wrapper),'dev',
        '--mode','hybrid_dev','--backend','std_http','--lua-root',str(lua_root)],env=env,
        stdin=subprocess.PIPE,stdout=output,stderr=subprocess.STDOUT,
        creationflags=subprocess.CREATE_NEW_PROCESS_GROUP)
    try:
        url='http://127.0.0.1:'+str(number)+'/health'
        request(url,b'before edit',180,session)
        entry.write_text(application('after edit'))
        request(url,b'after edit',90,session)
        session.send_signal(signal.CTRL_BREAK_EVENT)
        session.wait(timeout=15)
        with socket.socket() as connection:
            assert connection.connect_ex(('127.0.0.1',number))!=0,'dev server survived session cancellation'
        print('PASS: Windows dev startup, source edit, refresh and process-tree shutdown',flush=True)
    except BaseException:
        print(devlog.read_text(errors='replace'),flush=True)
        raise
    finally:
        if session.poll() is None:
            session.kill(); session.wait(timeout=10)
