const bodyParser = require('body-parser')
const cors = require('cors');
const redis = require('redis');
const app = require("express")();
const PORT = 8080;

let data = {}

let publisherClient = redis.createClient(6379, process.argv[2])
let subscriberClient = redis.createClient(6379, process.argv[2])

subscriberClient.subscribe('newData');
subscriberClient.on('message', (channel, dataRedis)=> {
        let dataJson = JSON.parse(dataRedis)
        data[dataJson.key] = dataJson.value
    })

app.use(cors())
app.use(bodyParser.json());
app.use(bodyParser.urlencoded({ extended: false }));

app.post('/put', (req,res) => {
    let {key,value} = req.body

    if(!key || !value){
        res.json('Missing key and/or value')
    }
    else {
        data[key] = value
        publisherClient.publish('newData', JSON.stringify({key,value}))
        res.json('Data stored')
    }
})

app.get('/get', (req,res) => {
    let {key} = req.body

    if(!data[key]){
        res.json('Data not found')
    }
    else{
        res.json(data[key])
    }
})

app.listen(PORT,() => {
    console.log('Listening on port %d!',PORT);
});

