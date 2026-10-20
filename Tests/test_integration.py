import struct
import zlib
import concurrent.futures
import json
import os
from pathlib import Path
import subprocess
import tempfile

BASE = Path(__file__).resolve().parent
BIN = Path(os.environ.get('PAPER_MEMORY_TEST_BINARY', str(BASE.parent / 'build/PaperMemory.app/Contents/MacOS/PaperMemory')))

def run_tests():
    with tempfile.TemporaryDirectory(prefix='paper-test-') as root:
        env = dict(os.environ, PAPER_MEMORY_HOME=root, PAPER_MEMORY_NO_LAUNCH='1')
        def call(method, args=None, ok=True):
            p = subprocess.run([str(BIN), '--cli', method], input=json.dumps(args or {}, ensure_ascii=False), text=True, capture_output=True, env=env)
            result = json.loads(p.stdout)
            assert result['ok'] == ok, (method, result, p.stderr)
            assert p.returncode == (0 if ok else 1)
            return result.get('data', result)
        call('health')
        n = call('create', {'summary': '跟进报价\n确认交付时间', 'details': '来自讨论的完整背景', 'category': '客户跟进', 'sourceName': '飞书'})
        assert call('get', {'id': n['id']})['summary'] == '跟进报价\n确认交付时间'
        assert call('context')['categories'] == ['客户跟进']
        call('create', {'summary': '字' * 61}, ok=False)
        call('create', {'summary': '\n'.join(['一'] * 7)}, ok=False)
        call('create', {'summary': '允许多行\n内容'}, ok=True)
        call('create', {'summary': 'test', 'pinned': 'yes'}, ok=False)
        call('create', {'summary': 'test', 'fontSize': 24}, ok=False)
        call('create', {'summary': 'test', 'fontSize': True}, ok=False)
        call('create', {'summary': 'test', 'fontStyle': 'unknown'}, ok=False)
        call('create', {'summary': 'test', 'fontStyle': 2}, ok=False)
        call('create', {'summary': 'test', 'unknown': True}, ok=False)
        call('create', {'summary': 'test', 'sourceURL': 'javascript:alert(1)'}, ok=False)
        call('update', {'id': n['id'], 'summary': 'missing revision'}, ok=False)
        n2 = call('update', {'id': n['id'], 'expectedRevision': n['revision'], 'details': '更新后背景', 'fontSize': 26, 'fontStyle': 'cao'})
        assert n2['fontSize'] == 26 and n2['fontStyle'] == 'cao'
        call('update', {'id': n['id'], 'expectedRevision': n['revision'], 'details': '不能覆盖'}, ok=False)
        assert call('get', {'id': n['id']})['details'] == '更新后背景'
        completed = call('complete', {'id': n['id'], 'expectedRevision': n2['revision']})
        assert n['id'] not in [x['id'] for x in call('list')]
        restored = call('restore', {'id': n['id'], 'expectedRevision': completed['revision']})
        assert restored['completed'] is False
        image_path = Path(root) / 'source.png'
        def chunk(kind, data):
            return struct.pack('!I', len(data)) + kind + data + struct.pack('!I', zlib.crc32(kind + data))
        image_path.write_bytes(b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('!IIBBBBB', 32, 32, 8, 2, 0, 0, 0)) + chunk(b'IDAT', zlib.compress((b'\x00' + b'\xff\xe8\x99' * 32) * 32)) + chunk(b'IEND', b''))
        attached = call('attach', {'id': n['id'], 'expectedRevision': restored['revision'], 'path': str(image_path)})
        image_path.unlink()
        assert (Path(root) / 'attachments' / attached['attachments'][0]['file']).is_file()
        with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
            created = list(pool.map(lambda i: call('create', {'summary': f'并发便签 {i}', 'category': '测试'}), range(24)))
        assert len(call('list')) == 26
        assert len({x['id'] for x in call('list')}) == 26
        first, second = created[:2]
        call('organize', {'assignments': [{'id': first['id'], 'expectedRevision': first['revision'], 'category': '项目'}, {'id': second['id'], 'expectedRevision': 99, 'category': '项目'}]}, ok=False)
        assert call('get', {'id': first['id']})['category'] == '测试'
        organized = call('organize', {'assignments': [{'id': x['id'], 'expectedRevision': x['revision'], 'category': '项目'} for x in created]})
        assert len(organized) == 24 and len(call('list', {'category': '项目'})) == 24
        p = subprocess.Popen([str(BIN), '--mcp'], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, env=env)
        def rpc(i, method, params=None):
            p.stdin.write(json.dumps({'jsonrpc': '2.0', 'id': i, 'method': method, 'params': params or {}}, ensure_ascii=False) + '\n'); p.stdin.flush()
            return json.loads(p.stdout.readline())
        assert rpc(1, 'initialize', {'protocolVersion': '2025-06-18'})['result']['capabilities']['tools'] == {'listChanged': False}
        p.stdin.write('{"jsonrpc":"2.0","method":"notifications/initialized"}\n'); p.stdin.flush()
        assert len(rpc(2, 'tools/list')['result']['tools']) == 10
        result = rpc(3, 'tools/call', {'name': 'paper_create', 'arguments': {'summary': 'MCP 也能贴便签\n并自动归类', 'category': 'AI'}})['result']
        assert result['isError'] is False and result['structuredContent']['data']['category'] == 'AI'
        assert rpc(4, 'tools/call', {'name': 'paper_create', 'arguments': {'summary': '未分类字段'}})['result']['isError'] is True
        assert rpc(5, 'tools/call', {'name': 'unknown'})['error']['code'] == -32602
        mcp_note = result['structuredContent']['data']
        updated_result = rpc(6, 'tools/call', {'name': 'paper_update', 'arguments': {'id': mcp_note['id'], 'expectedRevision': mcp_note['revision'], 'summary': 'MCP 更新验证\nUpdated from AI', 'details': '详情也通过 AI 同步', 'pinned': False}})['result']
        assert updated_result['isError'] is False
        mcp_updated = updated_result['structuredContent']['data']
        readback = rpc(7, 'tools/call', {'name': 'paper_get', 'arguments': {'id': mcp_note['id']}})['result']['structuredContent']['data']
        assert readback == mcp_updated and readback['details'] == '详情也通过 AI 同步' and readback['pinned'] is False
        stale = rpc(8, 'tools/call', {'name': 'paper_update', 'arguments': {'id': mcp_note['id'], 'expectedRevision': mcp_note['revision'], 'summary': '不能覆盖'}})['result']
        assert stale['isError'] is True
        invalid = rpc(9, 'tools/call', {'name': 'paper_create', 'arguments': {'summary': '字' * 61, 'category': '测试'}})['result']
        assert invalid['isError'] is True
        assert rpc(10, 'tools/call', {'name': 'paper_get', 'arguments': {'id': mcp_note['id']}})['result']['structuredContent']['data'] == mcp_updated
        archived_mcp = rpc(11, 'tools/call', {'name': 'paper_complete', 'arguments': {'id': mcp_updated['id'], 'expectedRevision': mcp_updated['revision']}})['result']['structuredContent']['data']
        assert archived_mcp['completed'] is True
        restored_mcp = rpc(12, 'tools/call', {'name': 'paper_restore', 'arguments': {'id': archived_mcp['id'], 'expectedRevision': archived_mcp['revision']}})['result']['structuredContent']['data']
        assert restored_mcp['completed'] is False
        p.stdin.close(); p.wait(timeout=10)
        # Corrupt input must not get silently replaced with an empty store.
        store_file = Path(root) / 'notes.json'; store_file.write_text('{broken')
        call('create', {'summary': 'should not overwrite'}, ok=False)
        assert store_file.read_text() == '{broken'
        assert (Path(root) / 'notes.backup.json').is_file()
        print('PASS: multiline, limits, persistence, schema validation, revision conflicts, complete/restore, image copying, 24 concurrent writes, atomic categorization, MCP handshake/tools and corrupt-file preservation')

if __name__ == '__main__':
    run_tests()
