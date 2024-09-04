B4J=true
Group=Default Group
ModulesStructureVersion=1
Type=Class
Version=4.19
@EndOfDesignText@
'Class module
Sub Class_Globals
	#If MySQL
	Private pool As ConnectionPool
	Private JdbcUrl As String
	Private DriverClass As String
	Private User As String
	Private Password As String
	Private DBName As String
	#Else If SQLite
	Private DBDir As String
	Private DBFile As String
	#End If
	Private sql As SQL
	Private DebugQueries As Boolean
	Private commands As Map
End Sub

Public Sub Initialize
	#if DEBUG
	DebugQueries = True
	#else
	DebugQueries = False
	#end if
	LoadSQLCommands(Main.config)
End Sub

Public Sub GetCommand (Key As String) As String
	If commands.ContainsKey(Key) = False Then
		Log("*** Command not found: " & Key)
	End If
	Return commands.Get(Key)
End Sub

Public Sub GetConnection As SQL
	If DebugQueries Then LoadSQLCommands(Main.config)
	#If MySQL
	Return pool.GetConnection
	#Else If SQLite
	sql.InitializeSQLite(DBDir, DBFile, False)
	Return sql
	#End If
End Sub

Private Sub LoadSQLCommands (config As Map)
	Dim newCommands As Map
	newCommands.Initialize
	For Each k As String In config.Keys
		If k.StartsWith("sql.") Or _
			k.StartsWith("MySQL.") Or _
			k.StartsWith("SQLite.") Then
			newCommands.Put(k, config.Get(k))
		End If
	Next
	commands = newCommands
End Sub

Public Sub CheckDatabase (config As Map)
	Try
		Dim DBFound As Boolean
		Log($"Checking database..."$)
		#If MySQL
		Dim JdbcUrl As String = config.Get("MySQL.JdbcUrl")
		JdbcUrl = JdbcUrl.Replace("{DBName}", "information_schema")
		DriverClass = config.Get("MySQL.DriverClass")
		User = config.Get("MySQL.User")
		Password = config.Get("MySQL.Password")
		DBName = config.Get("MySQL.DBName")
		sql.InitializeAsync("connection", DriverClass, JdbcUrl, User, Password)
		Wait For connection_Ready (Success As Boolean)
		If Success = False Then
			Log(LastException)
			If sql <> Null And sql.IsInitialized Then sql.Close
			Log("Application is terminated.")
			ExitApplication
		End If
		
		Dim strSQL As String = GetCommand("MySQL.CHECK_DATABASE")
		Dim res As ResultSet = sql.ExecQuery2(strSQL, Array As String(DBName))
		Do While res.NextRow
			DBFound = True
		Loop
		res.Close
		#Else If SQLite
		DBDir = config.Get("SQLite.DBDir")
		DBFile = config.Get("SQLite.DBFile")
		DBDir = DBDir.Trim
		If DBDir = "" Then DBDir = File.DirApp
		If File.Exists(DBDir, DBFile) Then
			DBFound = True
		End If
		#End If

		If DBFound Then
			Log("Database found!")
			If sql <> Null And sql.IsInitialized Then sql.Close
			Main.StartServer
		Else
			CreateDatabase
		End If
	Catch
		LogError(LastException)
	End Try
End Sub

Private Sub CreateDatabase
	Log("Creating database...")
	#If MySQL
	ConAddSQLQuery(sql, "MySQL.CREATE_DATABASE")
	ConAddSQLQuery(sql, "MySQL.USE_DATABASE")
	ConAddSQLQuery(sql, "MySQL.create_table_users")
	ConAddSQLQuery(sql, "sql.insert_dummy_users")
	ConAddSQLQuery(sql, "MySQL.create_table_animals")
	ConAddSQLQuery(sql, "sql.insert_dummy_animals")
	#Else If SQLite
	sql.InitializeSQLite(DBDir, DBFile, True)
	sql.ExecNonQuery("PRAGMA journal_mode = wal")
	ConAddSQLQuery(sql, "SQLite.create_table_users")
	ConAddSQLQuery(sql, "sql.insert_dummy_users")
	ConAddSQLQuery(sql, "SQLite.create_table_animals")
	ConAddSQLQuery(sql, "sql.insert_dummy_animals")
	#End If

	Dim execution As Object = sql.ExecNonQueryBatch("SQL")
	Wait For (execution) SQL_NonQueryComplete (Success As Boolean)
	If Success Then
		Log("Database created successfully!")
		If sql <> Null And sql.IsInitialized Then sql.Close
		Main.StartServer
	Else
		Log("Error creating database!")
	End If
End Sub

Public Sub StartConnectionPool
	#If MySQL
	Log("Connecting to MySQL database...")
	Dim JdbcUrl As String = Main.config.Get("MySQL.JdbcUrl")
	JdbcUrl = JdbcUrl.Replace("{DBName}", DBName)
	pool.Initialize(DriverClass, JdbcUrl, User, Password)
	#End If
End Sub

Private Sub ConAddSQLQuery (Comm As SQL, Key As String)
	Dim strSQL As String = GetCommand(Key)
	#If MySQL
	strSQL = strSQL.Replace("{DBName}", DBName)
	#End If
	If strSQL <> "" Then
		Log(strSQL)
		Comm.AddNonQueryToBatch(strSQL, Null)
	End If
End Sub