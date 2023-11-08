let express = require("express");
let app = new express();
app.set("view engine","ejs");

const knex = require("knex")({
    client: "mysql",
    connection: {
        host: "terraform-20231025181136992100000003.ctik8wp0iy1y.us-east-2.rds.amazonaws.com",
        user: "admin",
        password: "catchemall",
        database: "pokemon_db",
        port: 3306,
    },
});

app.get("/", (req, res) => {
    knex
        .select()
        .from("poke_table")
        .then((result) => {
            console.log(result);
            let aPokemonList = result
            res.render("index",{aPokemonList: result});
        });
    });
    app.use('/pokemon', express.static('pokemon'));
    app.use('/public',express.static('public'));
    app.listen(3000)
