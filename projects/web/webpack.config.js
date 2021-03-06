var webpack = require("webpack");

module.exports = (env) => {
  return {
    entry: "./src/index.tsx",
    output: {
      filename: "bundle.js",
      path: __dirname + "/dist",
    },

    // Options for webpack-dev-server
    devServer: {
      publicPath: "/dist/",
      historyApiFallback: {
        index: 'index.html'
      },
      open: true // Open automatically in a browser
    },

    // Enable sourcemaps for debugging webpack's output.
    devtool: "source-map",

    resolve: {
      // Add '.ts' and '.tsx' as resolvable extensions.
      extensions: [".ts", ".tsx", ".js", ".json"],
    },
    module: {
      rules: [
        // All files with a '.ts' or '.tsx' extension will be handled by 'awesome-typescript-loader'.
        { test: /\.tsx?$/, loader: "awesome-typescript-loader" },

        // All output '.js' files will have any sourcemaps re-processed by 'source-map-loader'.
        { enforce: "pre", test: /\.js$/, loader: "source-map-loader" }
      ]
    },

    // When importing a module whose path matches one of the following, just
    // assume a corresponding global variable exists and use that instead.
    // This is important because it allows us to avoid bundling all of our
    // dependencies, which allows browsers to cache those libraries between builds.
    externals: {
      "react": "React",
      "react-dom": "ReactDOM",
      "auth0": "Auth0",
    },

    plugins: [
      new webpack.DefinePlugin({
        'OR_SERVICE_URL': JSON.stringify(env.production
                                         ? 'https://registry.mirza.d61.io'
                                         : 'http://localhost:8200'),
        'GOOGLE_MAPS_API_KEY': JSON.stringify(process.env.GOOGLE_MAPS_API_KEY),
      }),
    ]
  };
}
