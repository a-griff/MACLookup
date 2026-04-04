'
' -------------------------------------------------------
' MACLookup.bas (FreeBASIC)
' Version: 1.0
' -------------------------------------------------------

Dim Shared CONFIG_FILE As String

' ---- SETTINGS ----
Dim Shared USE_ONLINE As Integer
Dim Shared CURL_TIMEOUT As Integer
Dim Shared ENABLE_NMAP_LOOKUP As String
Dim Shared NMAP_DB As String
Dim Shared ENABLE_CACHE_FILE As String
Dim Shared CACHE_FILE As String
Dim Shared ENABLE_ONLINE_LOOKUP As String

' ---- PREFIX DATABASE ----
Type DBEntry
    name As String
    prefixes As String
End Type

Dim Shared DB() As DBEntry

' -------------------------------------------------------
' HELPERS
' -------------------------------------------------------

Function my_replace(ByVal s As String, ByVal findstr As String, ByVal repl As String) As String
    Dim p As Integer
    Dim outstr As String

    outstr = s
    p = Instr(outstr, findstr)

    Do While p > 0
        outstr = Left(outstr, p - 1) & repl & Mid(outstr, p + Len(findstr))
        p = Instr(outstr, findstr)
    Loop

    my_replace = outstr
End Function

Function strip_quotes(ByVal s As String) As String
    strip_quotes = my_replace(s, Chr(34), "")
End Function

Function strip_colon(ByVal s As String) As String
    strip_colon = my_replace(s, ":", "")
End Function

Function get_token(ByVal s As String, ByVal delim As String, ByVal indexnum As Integer) As String
    Dim i As Integer
    Dim p As Integer
    Dim tmp As String

    tmp = s

    For i = 0 To indexnum
        p = Instr(tmp, delim)

        If p = 0 Then
            If i = indexnum Then
                get_token = tmp
            Else
                get_token = ""
            End If
            Exit Function
        End If

        If i = indexnum Then
            get_token = Left(tmp, p - 1)
            Exit Function
        End If

        tmp = Mid(tmp, p + Len(delim))
    Next

    get_token = ""
End Function

Function run_cmd(ByVal cmd As String) As String
    Dim f As Integer
    Dim result_text As String
    Dim linebuf As String

    result_text = ""
    f = FreeFile

    Open Pipe cmd For Input As #f
    Do While Not EOF(f)
        Line Input #f, linebuf
        result_text = result_text & linebuf
    Loop
    Close #f

    run_cmd = result_text
End Function

' -------------------------------------------------------
' INIT DEFAULTS
' -------------------------------------------------------
Sub init_defaults()

    CONFIG_FILE = "./MACLookup.conf"

    USE_ONLINE = 1
    CURL_TIMEOUT = 3
    ENABLE_NMAP_LOOKUP = "y"
    NMAP_DB = "/usr/share/nmap/nmap-mac-prefixes"
    ENABLE_CACHE_FILE = "y"
    CACHE_FILE = "./maclookup.cache"
    ENABLE_ONLINE_LOOKUP = "y"

End Sub

' -------------------------------------------------------
' CREATE CONFIG
' -------------------------------------------------------
Sub create_default_config()

    Dim f As Integer
    f = FreeFile
    Open CONFIG_FILE For Output As #f

    Print #f, "# ---- SETTINGS ----"
    Print #f, "USE_ONLINE=1"
    Print #f, "CURL_TIMEOUT=3"
    Print #f, "ENABLE_NMAP_LOOKUP=""y"""
    Print #f, "NMAP_DB=""/usr/share/nmap/nmap-mac-prefixes"""
    Print #f, "ENABLE_CACHE_FILE=""y"""
    Print #f, "CACHE_FILE=""./maclookup.cache"""
    Print #f, "ENABLE_ONLINE_LOOKUP=""y"""
    Print #f, ""
    Print #f, "# ---- PREFIX DATABASE ----"
    Print #f, "DB=("
    Print #f, """Amcrest Technologies|9C:8E:CD,A0:60:32"""
    Print #f, """Cinnado|02:07:25"""
    Print #f, ")"

    Close #f

End Sub

' -------------------------------------------------------
' LOAD CONFIG
' -------------------------------------------------------
Sub load_config()

    Dim f As Integer
    Dim inDB As Integer
    Dim idx As Integer
    Dim linebuf As String
    Dim key As String
    Dim sval As String

    If Dir(CONFIG_FILE) = "" Then
        create_default_config()
    End If

    f = FreeFile
    Open CONFIG_FILE For Input As #f

    inDB = 0
    idx = -1

    Do While Not EOF(f)

        Line Input #f, linebuf
        linebuf = Trim(linebuf)

        If linebuf = "" Then Continue Do
        If Left(linebuf, 1) = "#" Then Continue Do

        If linebuf = "DB=(" Then
            inDB = 1
            Continue Do
        End If

        If linebuf = ")" Then
            inDB = 0
            Continue Do
        End If

        If inDB = 1 Then
            idx = idx + 1
            ReDim Preserve DB(idx)

            linebuf = strip_quotes(linebuf)

            DB(idx).name = get_token(linebuf, "|", 0)
            DB(idx).prefixes = get_token(linebuf, "|", 1)

            Continue Do
        End If

        If Instr(linebuf, "=") > 0 Then
            key = get_token(linebuf, "=", 0)
            sval = strip_quotes(get_token(linebuf, "=", 1))

            If key = "USE_ONLINE" Then USE_ONLINE = ValInt(sval)
            If key = "CURL_TIMEOUT" Then CURL_TIMEOUT = ValInt(sval)
            If key = "ENABLE_NMAP_LOOKUP" Then ENABLE_NMAP_LOOKUP = sval
            If key = "NMAP_DB" Then NMAP_DB = sval
            If key = "ENABLE_CACHE_FILE" Then ENABLE_CACHE_FILE = sval
            If key = "CACHE_FILE" Then CACHE_FILE = sval
            If key = "ENABLE_ONLINE_LOOKUP" Then ENABLE_ONLINE_LOOKUP = sval
        End If

    Loop

    Close #f

End Sub

' -------------------------------------------------------
' LOOKUPS
' -------------------------------------------------------
Function lookup_local_db(ByVal prefix As String) As String

    Dim i As Integer
    Dim plist As String
    Dim ptoken As String

    For i = 0 To UBound(DB)

        plist = DB(i).prefixes

        Do While Instr(plist, ",") > 0
            ptoken = get_token(plist, ",", 0)

            If prefix = ptoken Then
                lookup_local_db = DB(i).name
                Exit Function
            End If

            plist = Mid(plist, Len(ptoken) + 2)
        Loop

        If prefix = plist Then
            lookup_local_db = DB(i).name
            Exit Function
        End If

    Next

    lookup_local_db = ""

End Function

Function lookup_nmap(ByVal mac As String) As String

    Dim hexstr As String
    Dim lens(2) As Integer
    Dim i As Integer
    Dim key As String
    Dim cmd As String
    Dim result_text As String
    Dim firstspace As Integer

    If ENABLE_NMAP_LOOKUP <> "y" Then
        lookup_nmap = ""
        Exit Function
    End If

    If Dir(NMAP_DB) = "" Then
        lookup_nmap = ""
        Exit Function
    End If

    hexstr = strip_colon(mac)

    lens(0) = 9
    lens(1) = 7
    lens(2) = 6

    For i = 0 To 2

        key = Left(hexstr, lens(i))
        cmd = "grep -i '^" & key & "[[:space:]]' " & NMAP_DB & " | head -n1"
        result_text = run_cmd(cmd)

        If result_text <> "" Then
            firstspace = Instr(result_text, " ")

            If firstspace > 0 Then
                lookup_nmap = Trim(Mid(result_text, firstspace + 1))
                Exit Function
            End If
        End If

    Next

    lookup_nmap = ""

End Function

Function lookup_online(ByVal prefix As String) As String

    Dim clean As String
    Dim cmd As String
    Dim result_text As String

    If ENABLE_ONLINE_LOOKUP <> "y" Then
        lookup_online = ""
        Exit Function
    End If

    clean = strip_colon(prefix)
    cmd = "curl -s --max-time " & Str(CURL_TIMEOUT) & " https://api.macvendors.com/" & clean
    result_text = run_cmd(cmd)

    If Instr(LCase(result_text), "errors") = 0 Then
        lookup_online = result_text
    Else
        lookup_online = ""
    End If

End Function

' -------------------------------------------------------
' MAIN
' -------------------------------------------------------

Dim arg As String
Dim mac As String
Dim prefix As String
Dim found As String
Dim workarg As String

init_defaults()
load_config()

If __FB_ARGC__ < 2 Then
    Print "USAGE: MACLookup <MAC1,MAC2,...>"
    End
End If

arg = Command(1)

If arg = "-h" Or arg = "--help" Or arg = "-?" Then
    Print "USAGE: MACLookup <MAC1,MAC2,...>"
    End
End If

workarg = arg

Do While Instr(workarg, ",") > 0

    mac = UCase(get_token(workarg, ",", 0))
    workarg = Mid(workarg, Len(mac) + 2)

    prefix = Left(mac, 8)

    found = lookup_local_db(prefix)
    If found <> "" Then
        Print mac & " -> " & found
        Continue Do
    End If

    found = lookup_nmap(mac)
    If found <> "" Then
        Print mac & " -> (" & found & ")"
        Continue Do
    End If

    found = lookup_online(prefix)
    If found <> "" Then
        Print mac & " -> (" & found & ")"
    Else
        Print mac & " -> (unknown)"
    End If

Loop

If workarg <> "" Then

    mac = UCase(workarg)
    prefix = Left(mac, 8)

    found = lookup_local_db(prefix)
    If found <> "" Then
        Print mac & " -> " & found
    Else
        found = lookup_nmap(mac)
        If found <> "" Then
            Print mac & " -> (" & found & ")"
        Else
            found = lookup_online(prefix)
            If found <> "" Then
                Print mac & " -> (" & found & ")"
            Else
                Print mac & " -> (unknown)"
            End If
        End If
    End If

End If
