#
# ******************************************************************************************************
#	
#	HTTP-Proxy development server
#   
#   This server listens on http://locahost:8080 and [based on request paths] proxies requests to local HTTP server
#   or remote server.
# 
#	Copyright (c) 2012 Mindspace, LLC
# 
# ******************************************************************************************************
# 


# *************************************************
# HTTP_PROXY Server 
#
# This server willp proxy all GET/HEAD requests to either a remote web server
# or a local web server. This means that another HTTP server must be instantiated
# to provide responses to delegated local requests. 
#
# *************************************************

class HttpProxyServer

	sys       = require( 'util' )
	httpProxy = require( 'http-proxy' )


	 # An Http server implementation that uses a map of methods to decide
	 # action routing.
	 #
	 # @param {
	 #            proxy_regexp : /^\/api\/json/    // RegExp to test URL to determine in proxy is needed 
	 #            local_host   : "127.0.0.1" 	// [or 127.0.0.1]
	 #            local_port  : 8080
	 #            local_port   : 8000
	 #            remote_host  : "data.gridlinked.info"  // domainName or IP for remote server
	 #            remote_port  : 80
	 #         }
	 #
	constructor : () ->
		@proxy = httpProxy.createServer( handleRequest.bind(@) )
		return @


	start : ( @config ) ->
		@proxy.listen( @config.local_port )
		sys.puts( "HttpProxy Server running at http://localhost:#{@config.local_port}/" )
	
		# Hidden server for fallback, non-proxied web assets
		return new HttpServer().start( @config, true )
		

	# ****************************
	# Private methods
	# ****************************

	handleRequest = ( request, response,  proxy ) ->
		needProxy = @config.proxy_regexp.test( request.url )
		config      =
			port : if needProxy then @config.remote_port else @config.silent_port
			host : if needProxy then @config.remote_host else @config.local_host

		sys.puts( "Proxying request from `#{ request.url }` to `http://#{ config.host }:#{ config.port }#{ request.url }`." ) if needProxy

		request.headers.host = config.host
		proxy.proxyRequest( request, response, config )
		return	



# *************************************************
# HTTP Server 
# *************************************************

class HttpServer

	sys       = require( 'util' )
	http      = require( 'http' )
	url       = require( 'url' )

	 # An Http server implementation that uses a map of methods to decide
	 # action routing.
	 #
	 # @param {Object} Map of method => Handler function
	 #
	constructor : (@handlers) ->
		@handlers ||= { 'GET'  : createServlet( StaticServlet ), 'HEAD' : createServlet( StaticServlet ) } 	
		@server     = http.createServer( handleRequest.bind(@) )
		return @


	start : ( @config, silent=false ) ->
		# !! Add fallback, local web server port; default == `local_port + 100`
		@config.silent_port ||=  Number(@config.local_port) + 100

		@server.listen( @config.silent_port )
		sys.puts( "Http Server running at http://localhost:#{@config.silent_port}/" ) if ( !silent )
		return

	# ****************************
	# Private methods
	# ****************************

	createServlet = (Class) ->
		servlet = new Class()
		servlet.handleRequest.bind(servlet)


	parseURL = ( target ) ->
		parsed = url.parse( target )
		parsed.pathname = url.resolve('/',parsed.pathname)
		return url.parse( url.format(parsed), true )


	handleRequest = (req, res) ->
		logEntry  = "#{req.method} #{req.url}"
		logEntry += " #{req.headers['user-agent']}" if (req.headers['user-agent'])

		sys.puts( logEntry )
		req.url = parseURL(req.url)
		handler = @handlers[req.method]

		if ( !handler )
			res.writeHead(501)
			res.end()
			return
		
		handler.call(@,req,res)		




# *************************************************
# Static Servlet 
# *************************************************

class StaticServlet
		
	sys       = require( 'util' )
	fs        = require( 'fs' )
	url       = require( 'url' )


	MimeMap = 
		'coffee': 'text/plain'
		'txt'	: 'text/plain'
		'html'	: 'text/html'
		'css'	: 'text/css'
		'xml'	: 'application/xml'
		'json'	: 'application/json'
		'js'	: 'application/javascript'
		'jpg'	: 'image/jpeg'
		'jpeg'	: 'image/jpeg'
		'gif'	: 'image/gif'
		'png'	: 'image/png'


	handleRequest : (req, res) ->
		path = "./#{req.url.pathname}"
			.replace('//','/')
			.replace(/%(..)/, (match,hex) ->
				return String.fromCharCode( parseInt(hex,16) )
			)
		parts = path.split('/')

		return sendForbidden(req, res, path)       if (parts[parts.length-1].charAt(0) is '.')

		fs.stat(path, (err, stat) ->
			return sendMissing( req, res, path )   if err
			return sendDirectory( req, res, path ) if stat.isDirectory()

			return sendFile( req, res, path )      
		)
		

	# ****************************************************
	# Private Methods 
	# ****************************************************


	
	# Output File contents; with correct mimetype header
	#
	sendFile  = (req, res, path) ->
		cType = MimeMap[path.split('.').pop()]
		res.writeHead( 200, 'Content-Type': cType || 'text/html' ) 
		res.end() if req.method is 'HEAD'

		file  = fs.createReadStream(path)
		file.on( 'data',  res.write.bind(res) )
		file.on( 'close', () -> res.end() )
		file.on( 'error', (error) -> sendError(req,res,error) )
		return


	# Output HTML of directory content listing
	#
	sendDirectory =   (req, res, path) ->
		if ( path.match(/[^\/]$/) )
			req.url.pathname += '/'
			redirectUrl = url.format(
				url.parse(url.format(req.url))
			)
			return sendRedirect( req, res, redirectUrl )
		
		fs.readdir( path, (err, files) =>
			return sendError( req, res, error )              if err
			return writeDirectoryList( req, rees, path, [])  if !files.length

			numFiles = files.length
			files.forEach( (fileName, index) ->
				fs.stat( path, (err, stat) ->
					return sendMissing( req, res, path )   if err
					files[index] = fileName + '/'          if  stat.isDirectory()
 
					return writeDirectoryList(req, res, path, files) if ( !(--numFiles) )    
				)
			)
		)		
	
	
	# Output 500 response
	#
	sendError = (req, res, path) ->
		content = """
			<!DOCTYPE html>
			<html>
			  <head>
			  <title>Internal Server Error</title>
			  </head>
			  <body>
				<h1>Internal Server Error</h1>
				<pre>#{ escapeHtml(sys.inspect(error)) }#</pre>
			  </body>
			</html>
		"""
		res.writeHead( 500, 'Content-Type': 'text/html' ) 
		res.write( content )
		res.end()

		sys.puts('500 Internal Server Error');
		sys.puts(sys.inspect(error));
		return


	# Output 404 (Not Found) Response
	#
	sendMissing = (req, res, path) ->
		content = 	"""
			<!DOCTYPE html>
			<html>
			  <head>
			  <title>404 Not Found</title>
			  </head>
			  <body>
				<h1>Missing / Not Found</h1>
				<p>
				   The requested URL `#{ escapeHtml(path.substring(1)) }` 
				   was not found on this server.
				</p>
			  </body>
			</html>
		"""
		res.writeHead( 404, 'Content-Type': 'text/html' ) 
		res.write( content )
		res.end()

		sys.puts("404 Not Found: #{path}");
		return


	# Output 403 (Forbidden) response
	#
	sendForbidden = (req, res, path) ->
		content = 	"""
			<!DOCTYPE html>
			<html>
			  <head>
			  <title>403 Forbidden</title>
			  </head>
			  <body>
				<h1>Forbidden/h1>
				<p>
				   You do not have permission to access
				   `#{ escapeHtml(path.substring(1)) }` 
				   on this server.
				</p>
			  </body>
			</html>
		"""
		res.writeHead( 403, 'Content-Type': 'text/html' ) 
		res.write( content )
		res.end()

		sys.puts("403 Forbidden: #{path}");
		return

	# Output 301 (Redirect) response
	#
	sendRedirect = (req, res, redirectUrl) ->
		content = 	"""
			<!DOCTYPE html>
			<html>
			  <head>
			  <title>301 Moved Permanently</title>
			  </head>
			  <body>
				<h1>Moved Permanently/h1>
				<p>
				   The document has moved to <a href='#{redirectUrl}'> here </a>
				</p>
			  </body>
			</html>
		"""
		res.writeHead( 301, 
			'Content-Type': 'text/html' 
			'Location'    : redirectUrl 
		) 
		res.write( content )
		res.end()

		sys.puts("301 Moved Permanently: #{redirectUrl}");
		return



	# Output HTML listing of directory contents
	#
	writeDirectoryList = (req, res, path, files) ->		
		res.writeHead( 200, 'Content-Type': 'text/html' ) 
		return res.end() if (req.method is 'HEAD')

		rows = ""
		files.forEach( (name) ->
			if ( name.charAt(0) isnt '.' )
			    name  =  name.substring(0,name.length-1) if (name.charAt(name.length-1) is '/')
				rows +=  "<li><a href=\"#{name}\">#{name}</a></li>"
		)

		content = """
			<!DOCTYPE html>
			<html>
			  <head>
				  <title>"#{ escapeHtml(path) }"</title>
				  <style>
				  	ol {
				  		list-style-type: none;
				  		font-size      : 1.2em;
				  	}
				  </style>
			  </head>
			  <body>
				<h1>Directory: #{ escapeHtml(path) }</h1>
				<ol>
					#{rows}
				</ol>
			  </body>
			</html>
		"""

		res.write( content )
		res.end()
		return


	# ************************************
	# Private Utility methods
	# ************************************

	escapeHtml = (value) ->
		value.toString()
			.replace('<', '&lt;')
			.replace('>', '&gt;')
			.replace('"', '&quot;')



# ************************************************
# Exports classes required  (2) servers
# ************************************************

exports.StaticServlet   = StaticServlet
exports.HttpServer      = HttpServer
exports.HttpProxyServer = HttpProxyServer

