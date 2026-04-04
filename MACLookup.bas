' -------------------------------------------------------
' MACLookup.bas (FreeBASIC)
' Version: 1.0
' -------------------------------------------------------

Dim Shared CONFIG_FILE As String

Dim Shared USE_ONLINE As Integer
Dim Shared CURL_TIMEOUT As Integer
Dim Shared ENABLE_NMAP_LOOKUP As String
Dim Shared NMAP_DB As String
Dim Shared ENABLE_CACHE_FILE As String
Dim Shared CACHE_FILE As String
Dim Shared ENABLE_ONLINE_LOOKUP As String

Type DBEntry
    name As String
    prefixes As String
End Type

Dim Shared DB() As DBEntry

' ---------------- HELPERS ----------------

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

Function normalize_mac(ByVal s As String) As String
    Dim clean As String
    Dim i As Integer
    Dim outstr As String

    clean = UCase(s)
    clean = my_replace(clean, ":", "")
    clean = my_replace(clean, "-", "")
    clean = my_replace(clean, ".", "")

    outstr = ""
    For i = 1 To Len(clean) Step 2
        If i > 1 Then outstr = outstr & ":"
        outstr = outstr & Mid(clean, i, 2)
    Next

    normalize_mac = outstr
End Function

Function get_token(ByVal s As String, ByVal delim As String, ByVal indexnum As Integer) As String
    Dim i As Integer
    Dim p As Integer
    Dim tmp As String

    tmp = s

    For i = 0 To indexnum
        p = Instr(tmp, delim)

        If p = 0 Then
            If i = indexnum Then get_token = tmp Else get_token = ""
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
    Dim outtxt As String
    Dim linebuf As String

    outtxt = ""
    f = FreeFile

    Open Pipe cmd For Input As #f
    Do While Not EOF(f)
        Line Input #f, linebuf
        outtxt = outtxt & linebuf
    Loop
    Close #f

    run_cmd = outtxt
End Function

' ---------------- INIT ----------------

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

' ---------------- LOOKUPS ----------------

Function lookup_local_db(ByVal mac As String) As String
    Dim i As Integer
    Dim plist As String
    Dim token As String
    Dim best_match As String
    Dim best_len As Integer
    Dim tlen As Integer

    best_match = ""
    best_len = 0

    For i = 0 To UBound(DB)
        plist = DB(i).prefixes

        Do
            token = get_token(plist, ",", 0)
            If token = "" Then token = plist

            tlen = Len(token)

            If Left(mac, tlen) = token Then
                If tlen > best_len Then
                    best_len = tlen
                    best_match = DB(i).name
                End If
            End If

            If Instr(plist, ",") > 0 Then
                plist = Mid(plist, Len(token) + 2)
            Else
                Exit Do
            End If
        Loop
    Next

    lookup_local_db = best_match
End Function

Function lookup_nmap(ByVal mac As String) As String
    Dim hexstr As String
    Dim key As String
    Dim cmd As String
    Dim outtxt As String
    Dim spcpos As Integer
    Dim lens(2) As Integer = {9,7,6}
    Dim i As Integer

    If ENABLE_NMAP_LOOKUP <> "y" Then Exit Function
    If Dir(NMAP_DB) = "" Then Exit Function

    hexstr = strip_colon(mac)

    For i = 0 To 2
        key = Left(hexstr, lens(i))
        cmd = "grep -i '^" & key & "[[:space:]]' " & NMAP_DB & " | head -n1"
        outtxt = run_cmd(cmd)

        If outtxt <> "" Then
            spcpos = Instr(outtxt, " ")
            If spcpos > 0 Then
                lookup_nmap = Trim(Mid(outtxt, spcpos + 1))
                Exit Function
            End If
        End If
    Next

    lookup_nmap = ""
End Function

Function lookup_online(ByVal prefix As String) As String
    Dim clean As String
    Dim cmd As String
    Dim outtxt As String

    If ENABLE_ONLINE_LOOKUP <> "y" Then Exit Function

    clean = strip_colon(prefix)
    cmd = "curl -s --max-time " & Str(CURL_TIMEOUT) & " https://api.macvendors.com/" & clean
    outtxt = run_cmd(cmd)

    If Instr(LCase(outtxt), "errors") = 0 Then
        lookup_online = outtxt
    Else
        lookup_online = ""
    End If
End Function

' ---------------- MAIN ----------------

Dim arg As String
Dim mac As String
Dim prefix As String
Dim found As String

init_defaults()

If __FB_ARGC__ < 2 Then
    Print "USAGE: MACLookup <MAC1,MAC2,...>"
    End
End If

arg = Command(1)

If arg = "-h" Or arg = "--help" Or arg = "-?" Then
    Print "USAGE: MACLookup <MAC1,MAC2,...>"
    End
End If

Do

    mac = normalize_mac(get_token(arg, ",", 0))

    prefix = Left(mac, 8)

    found = lookup_local_db(mac)
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

    If Instr(arg, ",") > 0 Then
        arg = Mid(arg, Len(get_token(arg, ",", 0)) + 2)
    Else
        Exit Do
    End If

Loop
