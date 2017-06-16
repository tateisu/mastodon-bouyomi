# mastodon-bouyomi
listening mastodon streaming api and send message text to BouyomiChan.

# 依存関係
- 棒読みちゃん http://chi.usamimi.info/Program/Application/BouyomiChan/
- cygwinにUTF-8なシェル
- curl
- perl
- use AnyEvent::HTTP;
- use AnyEvent::WebSocket::Client;
- use AnyEvent::Socket;

CygwinにAnyEvent系パッケージを入れるのがめんどくさいかも？

# 認証
以下のコマンドを実行すると認証してアクセストークンをaccess_info.json に保存します
```
perl StreamToBouyomi.pl -i mastodon.juggler.jp -u tateisu@gmail.com -p PASSWORD -c access_info.json
```

# ストリーミングデータの転送

access_info.json に保存されたインスタンス名とアクセストークンを使ってストリーミングAPIでタイムラインを受信します
```
perl StreamToBouyomi.pl -c access_info.json -s public:local,user
```

オプション詳細
```
  -i instance          : host name of instance
  -u user-mail-address : user mail address
  -p password          : user password
  -c config_file       : file to save instance-name,client_id,client_secret,access_token
  -v                   : verbose mode.
  -c config_file  : file to save/load instance-name,client_id,client_secret,access_token
  -s stream-type  : comma-separated list of stream type. default is 'public:local'
  -v              : verbose mode.
  --bh host : host name or ip address of BouyomiChan
  --bp port : post number of BouyomiChan

```
