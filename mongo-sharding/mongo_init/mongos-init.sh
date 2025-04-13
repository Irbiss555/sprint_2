#!/bin/bash

echo "Ждём поднятие Mongo DB конфигурационного сервера"

until mongosh --host configsvr1 --eval "db.adminCommand('ping')" >/dev/null 2>&1; do
  echo "Ожидаем configsvr1..."
  sleep 2
done

echo "Инициализация конфигурационного репликасета"
mongosh --host configsvr1 --eval '
rs.initiate({
  _id: "rs-config-server",
  configsvr: true,
  members: [
    {_id: 0, host: "configsvr1:27017"},
    {_id: 1, host: "configsvr2:27017"},
    {_id: 2, host: "configsvr3:27017"}
  ]
})'

echo "Ожидание инициализации конфиг-сервера..."
sleep 10

echo "Инициализация шардов"
mongosh --host shard1 --port 27018 --eval '
rs.initiate({
  _id: "rs-shard1",
  members: [
    {_id: 0, host: "shard1:27018"}
  ]
})'

mongosh --host shard2 --port 27018 --eval '
rs.initiate({
  _id: "rs-shard2",
  members: [
    {_id: 0, host: "shard2:27018"}
  ]
})'

echo "Ждём завершения инициализации шардов..."
sleep 10

echo "Запуск mongos с конфигурацией"
mongos --configdb rs-config-server/configsvr1:27017,configsvr2:27017,configsvr3:27017 --bind_ip_all --port 27017 &
sleep 5

echo "Добавление шардов через mongos"
mongosh --host localhost --port 27017 <<EOF
sh.addShard("rs-shard1/shard1:27018");
sh.addShard("rs-shard2/shard2:27018");
sh.status();
sh.enableSharding("somedb");
sh.shardCollection("somedb.helloDoc", { "name" : "hashed" } )
use somedb
for(var i = 0; i < 1000; i++) db.helloDoc.insert({age:i, name:"ly"+i})
EOF

wait
