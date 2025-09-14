module.exports = {
  require: [
    'ts-node/register/transpile-only'
  ],
  extension: ['ts'],
  spec: ['test-js/**/*.ts'],
  timeout: 60000,
};
