const vm = require ('vm');
const fs = require ('fs');
const path = require('path');

var pkg = require('./package.json');

// Gobble up a JSON file with comments
function getJSON(filepath) {
  const jsonString = "g = " + fs.readFileSync(filepath, 'utf8') + "; g";
  return (new vm.Script(jsonString)).runInNewContext();
}

exports.default = function * (task) {
  yield task.serial(['build']);
}

exports.clean = function * (task) {
  yield task.clear(['coverage']);
}

exports.superclean = function * (task) {
  task.parallel(['clean']);
  yield task.clear(['lib'])
}

exports.mrproper = function * (task) {
  task.parallel(['superclean']);
  yield task.clear(['node_modules'])
}

exports.build = function * (task) {
  let coffeeops = getJSON('./coffeeconfig.json');
  yield task.serial(['superclean'])
    .source('src/**/*.coffee')
    .coffee(coffeeops)
    .target('lib')
}

exports.test = function * (task) {
  yield task.source("./tests/**/*.test.coffee")
    .shell({
      cmd: 'mocha --require coffee-script/register --require coffee-coverage/register-istanbul -u bdd --colors --reporter spec $glob',
      preferLocal: true,
      glob: true
    })
}

exports.lint = function * (task) {
  yield task.source('src tests')
    .shell({
      cmd: 'coffeelint $glob',
      preferLocal: true,
      glob: true
    })
}