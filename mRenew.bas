Attribute VB_Name = "mRenew"
Option Explicit

Public Sub ByImport( _
              ByRef rn_wb As Workbook, _
              ByVal rn_comp_name As String, _
              ByVal rn_exp_file_full_name As String)
' -----------------------------------------------------
' Renews/replaces the component (rn_comp_name) in
' Workbook (rn_wb) by importing the Export-File
' (rn_exp_file_full_name).
' Note: Because a module cannot be deleted it is
'       renamed and deleted. The rename puts it out of
'       the way, deletion is done by the system when
'       the process has ended.
' -----------------------------------------------------
    Dim sTempName       As String
    Dim sExpFilePath    As String
    Dim fso             As New FileSystemObject

    Debug.Print NowMsec & " =========================="
    SaveWbk rn_wb
    DoEvents:  Application.Wait Now() + 0.0000001 ' wait for 10 milliseconds
    With rn_wb.VBProject
        If CompExists(ce_wb:=rn_wb, ce_comp_name:=rn_comp_name) Then
            '~~ Find a free/unused temporary name
            sTempName = GetTempName(ac_wb:=rn_wb, ac_comp_name:=rn_comp_name)
            '~~ Rename the component when it already exists
            .VBComponents(rn_comp_name).Name = sTempName
            Debug.Print NowMsec & " '" & rn_comp_name & "' renamed to '" & sTempName & "'"
'           DoEvents:  Application.Wait Now() + 0.0000001 ' wait for 10 milliseconds
            .VBComponents.Remove .VBComponents(sTempName) ' will not take place until process has ended!
            Debug.Print NowMsec & " '" & sTempName & "' removed (may be postponed by the system however)"
        End If
    
        '~~ (Re-)import the component
        .VBComponents.Import rn_exp_file_full_name
        Debug.Print NowMsec & " '" & rn_comp_name & "' (re-)imported from '" & rn_exp_file_full_name & "'"
        sExpFilePath = rn_wb.Path & "\" & rn_comp_name & Extension(ext_wb:=rn_wb, ext_comp_name:=rn_comp_name)
        If Not fso.FileExists(sExpFilePath) Or rn_exp_file_full_name <> sExpFilePath Then
            .VBComponents(rn_comp_name).Export sExpFilePath
            Debug.Print NowMsec & " '" & rn_comp_name & "' exported to '" & sExpFilePath & "'"
        End If
    End With
          
    Set fso = Nothing
    
End Sub

Private Sub SaveWbk(ByRef rs_wb As Workbook)
    Application.EnableEvents = False
    rs_wb.Save
    Application.EnableEvents = True
End Sub

Private Function GetTempName(ByRef ac_wb As Workbook, _
                             ByVal ac_comp_name As String) As String
' Return a temporary name for a component not already existing
' ------------------------------------------------------------------
    Dim sTempName   As String
    Dim i           As Long
    
    sTempName = ac_comp_name & "_Temp"
    Do
        On Error Resume Next
        sTempName = ac_wb.VBProject.VBComponents(sTempName).Name
        If Err.Number <> 0 Then Exit Do ' a component with sTempName does not exist
        i = i + 1: sTempName = sTempName & i
    Loop
    GetTempName = sTempName
End Function

'Private Function WbkIsOpen(ByVal io_wb_full_name As String) As Boolean
'' Retuns True when the Workbook (io_full_name) is open.
'' --------------------------------------------------------------------
'    Dim fso     As New FileSystemObject
'    Dim xlApp   As Excel.Application
'
'    If Not fso.FileExists(io_wb_full_name) Then Exit Function
'    On Error Resume Next
'    Set xlApp = GetObject(io_wb_full_name).Application
'    WbkIsOpen = Err.Number = 0
'
'End Function

'Private Function WbkGetOpen(ByVal go_wb_full_name) As Workbook
'
'    Dim fso     As New FileSystemObject
'    Dim sWbName As String
'
'    If Not fso.FileExists(go_wb_full_name) Then Exit Function
'    If WbkIsOpen(go_wb_full_name) Then
'        Set WbkGetOpen = Application.Workbooks(sWbName)
'    Else
'        Set WbkGetOpen = Application.Workbooks.Open(go_wb_full_name)
'    End If
'
'    Set fso = Nothing
'
'End Function

Private Function CompExists(ByRef ce_wb As Workbook, _
                            ByVal ce_comp_name As String) As Boolean
' ------------------------------------------------------------------
' Returns TRUE when the component (ce_comp_name) exists in the
' Workbook ce_wb.
' ------------------------------------------------------------------
    Dim s As String
    On Error Resume Next
    s = ce_wb.VBProject.VBComponents(ce_comp_name).Name
    CompExists = Err.Number = 0
End Function

Private Function Extension(ByRef ext_wb As Workbook, _
                           ByVal ext_comp_name As String) As String
' -----------------------------------------------------------------
' Returns the components Export-File extension
' -----------------------------------------------------------------
    Select Case ext_wb.VBProject.VBComponents(ext_comp_name).Type
        Case vbext_ct_StdModule:    Extension = ".bas"
        Case vbext_ct_ClassModule:  Extension = ".cls"
        Case vbext_ct_MSForm:       Extension = ".frm"
        Case vbext_ct_Document:     Extension = ".cls"
    End Select
End Function

Private Property Get NowMsec() As String
    NowMsec = Format(Now(), "hh:mm:ss") & Right(Format(Timer, "0.000"), 4)
End Property

