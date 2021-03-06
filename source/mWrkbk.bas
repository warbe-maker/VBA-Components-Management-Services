Attribute VB_Name = "mWrkbk"
Option Explicit
Option Private Module
Option Compare Text
' -----------------------------------------------------------------------------------
' Standard Module mWrkbk: Provides basic common Workbook services.
'
' Public services:
' - GetOpen     Opens a provided Workbook if possible, returns the Workbook
'               object of the openend or an already open Workbook
' - IsFullName  Returns TRUE when a provided string is the full name of a
'               Workbook
' - IsName      Returns TRUE when a provided string is the name of a Workbook
' - IsObject    Returns TRUE when the provided variant is a Workbook (not
'               necessarily also open!)
' - IsOpen      Returns TRUE when the provided Workbook is open
' - Opened      Returns a Distionary of all open Workbooks in any application
'               instance with the Workbook's BaseName as the key and the Workbook
'               object a item.
'               Attention these (current) constraints:
'               - Does not include any open Addin-Workbook
'               - Does not include all Workbooks with the same BaseName but
'                 different extensions
'
' Uses:
' - Common Components mErH (in mTest only!)
'
' Requires: Reference to "Microsoft Scripting Runtine"
'           Reference to "Microsoft Visual Basic for Applications Extensibility ..."
'
' W. Rauschenberger, Berlin August 2019
' -----------------------------------------------------------------------------------
#Const VBE = 1              ' Requires a Reference to "Microsoft Visual Basis Extensibility ..."
' --- Begin of declarations to get all Workbooks of all running Excel instances
Private Declare PtrSafe Function FindWindowEx Lib "user32" Alias "FindWindowExA" (ByVal hWnd1 As LongPtr, ByVal hWnd2 As LongPtr, ByVal lpsz1 As String, ByVal lpsz2 As String) As LongPtr
Private Declare PtrSafe Function GetClassName Lib "user32" Alias "GetClassNameA" (ByVal hWnd As LongPtr, ByVal lpClassName As String, ByVal nMaxCount As LongPtr) As LongPtr
Private Declare PtrSafe Function IIDFromString Lib "ole32" (ByVal lpsz As LongPtr, ByRef lpiid As UUID) As LongPtr
Private Declare PtrSafe Function AccessibleObjectFromWindow Lib "oleacc" (ByVal hWnd As LongPtr, ByVal dwId As LongPtr, ByRef riid As UUID, ByRef ppvObject As Object) As LongPtr

Type UUID 'GUID
    Data1 As Long
    Data2 As Integer
    Data3 As Integer
    Data4(7) As Byte
End Type

Const IID_IDispatch As String = "{00020400-0000-0000-C000-000000000046}"
Const OBJID_NATIVEOM As LongPtr = &HFFFFFFF0
' --- End of declarations to get all Workbooks of all running Excel instances
' --- Error declarations
Const ERR_OWB01 = "A Workbook named '<>' is not open in any application instance!"
Const ERR_GOW01 = "A Workbook with the provided name (parameter vWb) is open. However it's location is '<>1' and not '<>2'!"
Const ERR_GOW02 = "A Workbook named '<>' (parameter vWb) is not open. A full name must be provided to get it opened!"
Const ERR_GOW03 = "A Workbook file named '<>' (parameter vWb) does not exist!"

Private Function AppErr(ByVal err_no As Long) As Long
' -----------------------------------------------------------------
' Used with Err.Raise AppErr(<l>).
' When the error number <l> is > 0 it is considered an "Application
' Error Number and vbObjectErrror is added to it into a negative
' number in order not to confuse with a VB runtime error.
' When the error number <l> is negative it is considered an
' Application Error and vbObjectError is added to convert it back
' into its origin positive number.
' ------------------------------------------------------------------
    If err_no < 0 Then
        AppErr = err_no - vbObjectError
    Else
        AppErr = vbObjectError + err_no
    End If
End Function

Private Function checkHwnds(ByRef xlApps() As Application, hWnd As LongPtr) As Boolean
' -----------------------------------------------------------------------------------------
'
' -----------------------------------------------------------------------------------------
    Const PROC = "checkHwnds"            ' This procedure's name for the error handling and execution tracking
    
    On Error GoTo eh
    Dim i As Long
    
    If UBound(xlApps) = 0 Then GoTo xt

    For i = LBound(xlApps) To UBound(xlApps)
        If xlApps(i).hWnd = hWnd Then
            checkHwnds = False
            GoTo xt
        End If
    Next i
    checkHwnds = True
    
xt: Exit Function
    
eh: ErrMsg ErrSrc(PROC)
End Function

Private Sub ErrMsg( _
             ByVal err_source As String, _
    Optional ByVal err_no As Long = 0, _
    Optional ByVal err_dscrptn As String = vbNullString)
' ------------------------------------------------------
' This Common Component does not have its own error
' handling. Instead it passes on any error to the
' caller's error handling.
' ------------------------------------------------------
    
    If err_no = 0 Then err_no = Err.Number
    If err_dscrptn = vbNullString Then err_dscrptn = Err.Description

    Application.EnableEvents = True
    Err.Raise Number:=err_no, Source:=err_source, Description:=err_dscrptn

End Sub

Private Function ErrSrc(ByVal sProc As String) As String
    ErrSrc = "mWrkbk" & "." & sProc
End Function

Private Function GetExcelObjectFromHwnd( _
                                  ByVal hWndMain As LongPtr) As Application
' -----------------------------------------------------------------------------------
'
' -----------------------------------------------------------------------------------
    Const PROC = "GetExcelObjectFromHwnd"

#If Win64 Then
    Dim hWndDesk As LongPtr
    Dim hWnd As LongPtr
#Else
    Dim hWndDesk As Long
    Dim hWnd As Long
#End If
    
    On Error GoTo eh
    Dim sText   As String
    Dim lRet    As Long
    Dim iid     As UUID
    Dim ob      As Object
    
    hWndDesk = FindWindowEx(hWndMain, 0&, "XLDESK", vbNullString)

    If hWndDesk <> 0 Then
        hWnd = FindWindowEx(hWndDesk, 0, vbNullString, vbNullString)

        Do While hWnd <> 0
            sText = String$(100, Chr$(0))
            lRet = CLng(GetClassName(hWnd, sText, 100))
            If Left$(sText, lRet) = "EXCEL7" Then
                Call IIDFromString(StrPtr(IID_IDispatch), iid)
                If AccessibleObjectFromWindow(hWnd, OBJID_NATIVEOM, iid, ob) = 0 Then 'S_OK
                    Set GetExcelObjectFromHwnd = ob.Application
                    GoTo xt
                End If
            End If
            hWnd = FindWindowEx(hWndDesk, hWnd, vbNullString, vbNullString)
        Loop
        
    End If
    
xt: Exit Function
    
eh: ErrMsg ErrSrc(PROC)
End Function

Public Function GetOpen(ByVal vWb As Variant) As Workbook
' -------------------------------------------------------
' Returns an open Workbook object or raises an error.
' If vWb is a full path-file name, the file exists but
' is not open it is opened.
' Note: A ReadOnly mode has to be set by the caller.
' -------------------------------------------------------
    Const PROC = "GetOpen"
    
    On Error GoTo eh
    Dim sTest       As String
    Dim sWbBaseName As String
    Dim sPath       As String
    Dim wbOpen      As Workbook
    Dim fso         As New FileSystemObject
        
    Set wbOpen = Nothing
    
    If Not mWrkbk.IsName(vWb) And Not mWrkbk.IsFullName(vWb) And Not mWrkbk.IsObject(vWb) _
    Then Err.Raise AppErr(1), ErrSrc(PROC), "The Workbook (parameter vWb) is neither a Workbook object nor a string (name or fullname)!"
    sWbBaseName = fso.GetBaseName(vWb)

    If mWrkbk.IsObject(vWb) Then
        Set wbOpen = vWb
    ElseIf mWrkbk.IsFullName(vWb) Then
        With Opened
            If fso.FileExists(sWbBaseName) Then
                '~~ A Workbook with the same name is open
                Set wbOpen = .Item(sWbBaseName)
                If wbOpen.FullName <> vWb Then
                    '~~ The open Workook with the same name is from a different location
                    If fso.FileExists(vWb) Then
                        '~~ The file still exists on the provided location
                        Err.Raise AppErr(3), ErrSrc(PROC), Replace(Replace$(ERR_GOW01, "<>1", wbOpen.Path), "<>2", sPath)
                    Else
                        '~~ The Workbook file does not or no longer exist at the provivded location.
                        '~~ The open one is apparenty the ment Workbook just moved to the new location.
                        Set wbOpen = wbOpen
                    End If
                Else
                    '~~ The open Workook is the one indicated by the provided full name
                    Set wbOpen = wbOpen
                End If
            Else
                '~~ The Workbook is yet not open
                If fso.FileExists(vWb) Then
                    Set wbOpen = Workbooks.Open(vWb)
                Else
                    Err.Raise AppErr(4), ErrSrc(PROC), Replace(ERR_GOW03, "<>", CStr(vWb))
                End If
            End If
        End With
    ElseIf mWrkbk.IsName(vWb) Then
        With Opened
            If .Exists(sWbBaseName) Then
                Set wbOpen = .Item(sWbBaseName)
            Else
                Err.Raise AppErr(5), ErrSrc(PROC), "A Workbook named '" & sWbBaseName & "' is not open and it cannot be opened since only the name is provided (a full name would be required)!"
            End If
        End With
    End If
    Set GetOpen = wbOpen
    
xt: Exit Function
    
eh: ErrMsg ErrSrc(PROC)
End Function

Public Function IsFullName(ByVal v As Variant) As Boolean
' -------------------------------------------------------
' Returns TRUE when v is an existing Workbook's FullName.
' -------------------------------------------------------
    Dim fso As New FileSystemObject
    
    If VarType(v) = vbString Then
        If fso.FileExists(v) Then
            Select Case fso.GetExtensionName(v)
                Case "xls", "xlm", "xlsm", "xlsb", "xlst", "xlam": IsFullName = True
            End Select
        End If
    End If
    
End Function

Public Function IsName(ByVal v As Variant) As Boolean
' ---------------------------------------------------
' Returns TRUE when (v) is a valid Workbook's file
' name due to its extension.
' ---------------------------------------------------
    Dim fso As New FileSystemObject
    
    If VarType(v) = vbString Then
        If v = vbNullString Then Exit Function
        Select Case fso.GetExtensionName(v)
                Case "xls", "xlm", "xlsm", "xlsb", "xlst", "xlam": IsName = True
        End Select
    End If
    Set fso = Nothing
End Function

Public Function IsObject(ByVal v As Variant) As Boolean
' -----------------------------------------------------
' Returns TRUE when v is a valid Workbook object.
' -----------------------------------------------------
    If VarType(v) = vbObject Then
        IsObject = TypeName(v) = "Workbook"
    End If
End Function

Public Function IsOpen(ByVal wb As Variant, _
              Optional ByRef wb_result As Workbook) As Boolean
' ------------------------------------------------------------
' Returns TRUE when the Workbook (wb) - which may be a Work-
' book object, a Workbook's name or fullname - is open in
' any Excel Application instance. If a fullname is provided
' and the file does not exist under this full name but a
' Workbook with the given name is open (but from another fol-
' der) the Workbook is regarded moved and thus is returned as
' open object(wb_result).
' ------------------------------------------------------------
    Const PROC = "IsOpen"
    
    On Error GoTo eh
    Dim OpenWbks As Dictionary
    Dim OpenWbk  As Workbook
    Dim fso         As New FileSystemObject
    Dim BaseName   As String
    
    If Not mWrkbk.IsObject(wb) And Not mWrkbk.IsFullName(wb) And Not mWrkbk.IsName(wb) And Not TypeName(wb) = "String" _
    Then Err.Raise AppErr(1), ErrSrc(PROC), "The Workbook (parameter wb) is neither a Workbook object nor a Workbook's name or fullname)!"
    BaseName = fso.GetBaseName(wb)
    
    Set OpenWbks = mWrkbk.Opened
    If mWrkbk.IsName(wb) Then
        '~~ wb is a Workbook's Name including its extension
        If OpenWbks.Exists(BaseName) Then
            '~~ A Workbook with the same 'BaseName' is open
            Set OpenWbk = OpenWbks.Item(BaseName)
            '~~ When a Workbook's Name is provided the Workbook is only regarde open when the open
            '~~ Workbook has the same name (i.e. including its extension)
            If fso.GetFile(OpenWbk.FullName).Name <> fso.GetFileName(wb) Then Set OpenWbk = Nothing
        End If
    ElseIf mWrkbk.IsFullName(wb) Then
        If OpenWbks.Exists(BaseName) Then
            '~~ A Workbook with the same 'BaseName' is open
            Set OpenWbk = OpenWbks.Item(BaseName)
            '~~ The provided (wb) specifies an exist Workbook file. This Workbook is regarded open (and returned as opject)
            '~~ when a Workbook with its Name (including the extension!) is open regardless in which location
            If fso.GetFile(OpenWbk.FullName).Name <> fso.GetFileName(wb) Then Set OpenWbk = Nothing
        End If
    ElseIf mWrkbk.IsObject(wb) Then
        If Opened.Exists(BaseName) Then
            Set OpenWbk = OpenWbks.Item(BaseName)
        End If
    Else
        '~~ If wb is a Workbook's BaseName it is regarded open when one with that BaseName is open
        '~~ regrdless its extension
        If OpenWbks.Exists(wb) Then Set OpenWbk = OpenWbks.Item(wb)
    End If
    
xt: If mWrkbk.IsObject(OpenWbk) Then
        IsOpen = True
        Set wb_result = OpenWbk
    End If
    Set fso = Nothing
    Exit Function
    
eh: ErrMsg ErrSrc(PROC)
End Function

Public Function Opened() As Dictionary
' -------------------------------------
' Returns a Dictionary of all currently
' open Workbooks in any running excel
' application instance with the
' Workbook's name (without extension!)
' as the key and the Workbook as item.
' -------------------------------------
    Const PROC  As String = "Opened"               ' This procedure's name for the error handling and execution tracking
    
    On Error GoTo eh
#If Win64 Then
    Dim hWndMain As LongPtr
#Else
    Dim hWndMain As Long
#End If
    Dim fso     As New FileSystemObject
    Dim lApps   As Long
    Dim wbk     As Workbook
    Dim aApps() As Application ' Array of currently active Excel applications
    Dim app     As Variant
    Dim dct     As New Dictionary
    Dim i       As Long

    hWndMain = FindWindowEx(0&, 0&, "XLMAIN", vbNullString)
    lApps = 0

    '~~ Collect all runing Excel instances in the array aApps
    Do While hWndMain <> 0
        Set app = GetExcelObjectFromHwnd(hWndMain)
        If Not (app Is Nothing) Then
            If lApps = 0 Then
                lApps = 1
                ReDim aApps(1 To 1)
                Set aApps(lApps) = app
            ElseIf checkHwnds(aApps, app.hWnd) Then
                lApps = lApps + 1
                ReDim Preserve aApps(1 To lApps)
                Set aApps(lApps) = app
            End If
        End If
        hWndMain = FindWindowEx(0&, hWndMain, "XLMAIN", vbNullString)
    Loop

    '~~ Collect all open Workbooks in a Dictionary and return it
    With dct
        .CompareMode = TextCompare
        For Each app In aApps
            For Each wbk In app.Workbooks
                If Not .Exists(fso.GetBaseName(wbk.Name)) Then .Add fso.GetBaseName(wbk.Name), wbk
            Next wbk
        Next app
    End With
    Set Opened = dct

xt: Exit Function
    
eh: ErrMsg ErrSrc(PROC)
End Function

Private Function TestSheet(ByVal wb As Workbook, _
                           ByVal vWs As Variant) As Worksheet
' -----------------------------------------------------------
' Returns the Worksheet object (vWs) - which may be a Work-
' sheet object or a Worksheet's name - of the Workbook (wb).
' Precondition: The Worksheet exists.
' -----------------------------------------------------------
    If VarType(vWs) = vbString Then
        Set TestSheet = wb.Worksheets(vWs)
    ElseIf TypeOf vWs Is Worksheet Then
        Set TestSheet = vWs
    End If
End Function

