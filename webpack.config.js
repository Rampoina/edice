var fs = require('fs');
var path = require('path');
var webpack = require('webpack');
var ExtractTextPlugin = require('extract-text-webpack-plugin');
var CopyWebpackPlugin = require('copy-webpack-plugin');


module.exports = {
  entry: [
    './html/elm-dice.js',
    './html/index.html',
    './html/elm-dice.css',
    //'./html/elm-dice-serviceworker.js',
  ],

  output: {
    path: path.join(__dirname, './dist'),
    filename: 'elm-dice.js'
  },

  resolve: {
    modules: [
      'node_modules',
      path.join(__dirname, "src"),
    ],
    extensions: ['.js', '.elm']
  },

  module: {
    rules: [
      {
        test: /\.(html|woff2|png|xml|ico|svg|json)$/,
        exclude: /node_modules/,
        use: [
          {
            loader: 'file-loader',
            options: {
              context: 'html',
              name: '[path][name].[ext]',
            },
          },
        ],
      },
      {
        test: /\.elm$/,
        exclude: [/elm-stuff/, /node_modules/],
        use: [ 'elm-webpack-loader' ],
      },
      {
        test: /\.css$/,
        use: ExtractTextPlugin.extract({
          fallback: 'style-loader',
          use: [
            { loader: 'css-loader', options: { importLoaders: 1 } },
            {
              loader: 'postcss-loader',
              options: {
                ident: 'postcss',
                plugins: function(loader) {
                  return [
                    require('autoprefixer')({ browsers: ['last 10 versions'] }),
                    require('postcss-partial-import')({
                      addDependencyTo: webpack,
                      prefix: '',
                      extension: '',
                    }),
                  ];
                },
              },
            },
          ],
        }),
      },
    ],
  },

  plugins: [
    new webpack.DefinePlugin({
      'process.env.NODE_ENV': '"production"'
    }),
    new ExtractTextPlugin("elm-dice.css"),
    new CopyWebpackPlugin([
      { from: 'html/manifest.json' },
      { from: 'html/favicons', to: 'favicons'},
      { from: 'html/favicon.ico' },
      { from: 'html/die.svg' },
      { from: 'html/elm-dice-serviceworker.js' },
      { from: 'html/cache-polyfill.js' },
      { from: 'html/sounds', to: 'sounds'},
    ]),
  ].concat(process.env.NODE_ENV === 'production'
    ? new webpack.optimize.UglifyJsPlugin({
        compress: { warnings: false }
      })
    : []),

  devServer: {
    host: '0.0.0.0',
    port: 5000,
    inline: true,
    stats: 'errors-only',
    contentBase: './html',
    historyApiFallback: true,
    disableHostCheck: true,
  }
};

