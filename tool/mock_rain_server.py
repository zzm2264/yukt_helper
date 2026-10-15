import urllib.request, json
# 本地测试 API 访问示例 (请将地址与 key 替换为实际部署的服务端参数)
req = urllib.request.Request(
    'http://127.0.0.1:5000/api/sync/download',
    headers={'Authorization': 'test_group_key'}
)
with urllib.request.urlopen(req, timeout=10) as resp:
    data = json.loads(resp.read().decode())
    print('Code:', data.get('code'))
    print('Count:', data.get('count'))
    for a in data.get('data', []):
        print('Name:', a.get('name'), 'Remark:', a.get('remark'), 'UID:', a.get('uid'), 'Expired:', a.get('expired'), 'HasPwd:', bool(a.get('pwd')), 'HasCookie:', bool(a.get('cookie')))