Attribute VB_Name = "mExport"
Option Explicit

Public Sub All()
' --------------------------------------------------------------
' Standard-Module mExport
'
' Public serviced:
' - All                 Exports all VBComponentnts whether the code
'                       has changed or not
' - ChangedComponents   Exports all VBComponents of which the code
'                       has changed, i.e. a temporary Export-File
'                       differs from the regular Export-File (of
'                       the previous code change).
'
' --------------------------------------------------------------
    Const PROC = "All"
    
    On Error GoTo eh
    Dim vbc     As VBComponent
    Dim sStatus As String
    Dim Comp    As clsComp
    
    mErH.BoP ErrSrc(PROC)
    
    '~~ Prevent any action when the required preconditins are not met
    If mService.Denied(PROC) Then GoTo xt
    
    sStatus = Log.Service

    '~~ Remove any obsolete Export-Files within the Workbook folder
    '~~ I.e. of no longer existing VBComponents or at an outdated location
    CleanUpObsoleteExpFiles
    
    If mMe.IsAddinInstnc _
    Then Err.Raise mErH.AppErr(1), ErrSrc(PROC), "The Workbook (active or provided) is the CompMan Addin instance which is impossible for this operation!"
    
    For Each vbc In mService.Serviced.VBProject.VBComponents
        Set Comp = New clsComp
        With Comp
            Set .Wrkbk = mService.Serviced
            .CompName = vbc.Name ' this assignment provides the name for the export file
            vbc.Export .ExpFileFullName
        End With
        Set Comp = Nothing
    Next vbc

xt: mErH.EoP ErrSrc(PROC)
    Exit Sub
    
eh: mErH.ErrMsg ErrSrc(PROC)
End Sub

Public Sub ChangedComponents()
' --------------------------------------------------------------------
' Exclusively performed/trigered by the Before_Save event:
' - Any code change (detected by the comparison of a temporary export
'   file with the current export file) is backed-up/exported
' - Outdated Export Files (components no longer existing) are removed
' - Clone code modifications update the raw code when confirmed by the
'   user
' --------------------------------------------------------------------------
    Const PROC = "ChangedComponents"
    
    On Error GoTo eh
    Dim vbc         As VBComponent
    Dim lComponents As Long
    Dim lRemaining  As Long
    Dim lExported   As Long
    Dim sExported   As String
    Dim bUpdated    As Boolean
    Dim lUpdated    As Long
    Dim sUpdated    As String
    Dim sMsg        As String
    Dim fso         As New FileSystemObject
    Dim v           As Variant
    Dim Comps       As clsComps
    Dim dctChanged  As Dictionary
    Dim Comp        As clsComp
    Dim RawComp     As clsRaw
    
    mErH.BoP ErrSrc(PROC)
    '~~ Prevent any action for a Workbook opened with any irregularity
    '~~ indicated by an '(' in the active window or workbook fullname.
    If mService.Denied(PROC) Then GoTo xt
    
    Set Stats = New clsStats
    Set Comps = New clsComps
        
    '~~ Remove any obsolete Export-Files within the Workbook folder
    '~~ I.e. of no longer existing VBComponents or at an outdated location
    CleanUpObsoleteExpFiles
        
    lComponents = mService.Serviced.VBProject.VBComponents.Count
    lRemaining = lComponents

    Set dctChanged = Comps.AllChanged ' selection of all changed components
    
    For Each v In dctChanged
        Set Comp = dctChanged(v)
        Set vbc = Comp.VBComp
        Log.ServicedItem = vbc
        DsplyProgress p_result:=sExported & " " & vbc.Name _
                    , p_total:=Stats.Total(sic_comps_changed) _
                    , p_done:=Stats.Total(sic_comps)
                
        Select Case Comp.KindOfComp
            Case enRawClone
                '~~ Establish a component class object which represents the cloned raw's remote instance
                '~~ which is hosted in another Workbook
                Set RawComp = New clsRaw
                With RawComp
                    '~~ Provide all available information rearding the remote raw component
                    '~~ Attention must be paid to the fact that the sequence of property assignments matters
                    .HostWrkbkFullName = mRawsHosted.HostFullName(comp_name:=Comp.CompName)
                    .CompName = Comp.CompName
                    .ExpFileExt = Comp.ExpFileExt  ' required to build the export file's full name
                    Set .ExpFile = fso.GetFile(.ExpFileFullName)
                    .CloneExpFileFullName = Comp.ExpFileFullName
                    .TypeString = Comp.TypeString
                    If Not .Changed(Comp) Then GoTo next_vbc
                End With
                
                If Comp.Changed And Not RawComp.Changed(Comp) Then
                    Log.Entry = "The Clone's code changed! (a temporary Export-File differs from the last regular Export-File)"
                    '~~ --------------------------------------------------------------------------
                    '~~ The code change in the clone component is now in question whether it is to
                    '~~ be ignored, i.e. the change is reverted with the Workbook's next open or
                    '~~ the raw code should be updated accordingly to make the change permanent
                    '~~ for all users of the component.
                    '~~ --------------------------------------------------------------------------
                    Comp.VBComp.Export Comp.ExpFileFullName
                    '~~ In case the raw had been imported manually the new check for a change will indicate no change
                    If RawComp.Changed(Comp, check_again:=True) Then GoTo next_vbc
                    Comp.ReplaceRawWithCloneWhenConfirmed raw:=RawComp, rwu_updated:=bUpdated ' when confirmed in user dialog
                    If bUpdated Then
                        lUpdated = lUpdated + 1
                        sUpdated = vbc.Name & ", " & sUpdated
                        Log.Entry = """Remote Raw"" has been updated with code of ""Raw Clone"""
                    End If
                        
                ElseIf Not Comp.Changed And RawComp.Changed(Comp) Then
                    '~~ -----------------------------------------------------------------------
                    '~~ The raw had changed since the Workbook's open. This case is not handled
                    '~~ along with the Workbook's Save event but with the Workbook's Open event
                    '~~ -----------------------------------------------------------------------
                    Log.Entry = "The Raw's code changed! (not considered with the export service)"
                    Log.Entry = "The Clone will be updated with the next Workbook open"
                End If
            
            Case enKindOfComp.enUnknown
                Stop '~~ This is supposed a sever coding error!
            
            Case Else ' enInternal, enHostedRaw
                With Comp
                    If .Changed Then
                        Log.Entry = "Code changed! (temporary Export-File differs from last changes Export-File)"
                        vbc.Export .ExpFileFullName
                        Log.Entry = "Exported to '" & .ExpFileFullName & "'"
                        lExported = lExported + 1
                        If lExported = 1 _
                        Then sExported = vbc.Name _
                        Else sExported = sExported & ", " & vbc.Name
                        GoTo next_vbc
                    End If
                
                    If .KindOfComp = enHostedRaw Then
                        If mRawsHosted.ExpFileFullName(comp_name:=.CompName) <> .ExpFileFullName Then
                            mRawsHosted.ExpFileFullName(comp_name:=.CompName) = .ExpFileFullName
                            Log.Entry = "Component's Export-File Full Name registered"
                        End If
                    End If
                End With
        End Select
                                
next_vbc:
        lRemaining = lRemaining - 1
        Set Comp = Nothing
        Set RawComp = Nothing
    Next v
    
    sMsg = Log.Service
    Select Case lExported
        Case 0:     sMsg = sMsg & "No code changed (of " & lComponents & " components)"
        Case Else:  sMsg = sMsg & sExported & " (" & lExported & " of " & lComponents & ")"
    End Select
    If Len(sMsg) > 255 Then sMsg = Left(sMsg, 251) & " ..."
    Application.StatusBar = sMsg
    
xt: Set dctHostedRaws = Nothing
    Set Comp = Nothing
    Set RawComp = Nothing
    Set Log = Nothing
    Set fso = Nothing
    mErH.EoP ErrSrc(PROC)   ' End of Procedure (error call stack and execution trace)
    Exit Sub
    
eh: Select Case mErH.ErrMsg(ErrSrc(PROC))
        Case mErH.DebugOptResumeErrorLine: Stop: Resume
        Case mErH.DebugOptResumeNext: Resume Next
        Case mErH.ErrMsgDefaultButton: End
    End Select
End Sub

Private Function ErrSrc(ByVal sProc As String) As String
    ErrSrc = "mExport." & sProc
End Function

Private Sub CleanUpObsoleteExpFiles()
' ------------------------------------------------------
' - Deletes all Export-Files for which the corresponding
'   component not or no longer exists.
' - Delete all Export-Files in another but the current
'   Export-Folder
' -------------------------------------------------------
    Const PROC = "CleanUpObsoleteExpFiles"
    
    On Error GoTo eh
    Dim cll     As Collection
    Dim fso     As New FileSystemObject
    Dim fl      As File
    Dim v       As Variant
    Dim Comp    As New clsComp
    Dim sExp    As String
    Dim fo      As Folder
    Dim fosub   As Folder
    
    sExp = mCompMan.ExpFileFolderPath(mService.Serviced) ' the current specified Export-Folder

    '~~ Cleanup of any Export-Files residing outside the specified 'Export-Folder'
    Set cll = New Collection
    cll.Add fso.GetFolder(mService.Serviced.Path)
    Do While cll.Count > 0
        Set fo = cll(1): cll.Remove 1 'get folder and dequeue it
        If fo.Path <> sExp Then
            For Each fosub In fo.SubFolders
                cll.Add fosub ' enqueue it
            Next fosub
            If fo.ParentFolder = mService.Serviced.Path Or fo.Path = mService.Serviced.Path Then
                '~~ Cleanup is done only in the Workbook-folder and any direct sub-folder
                '~~ Folders in sub-folders are exempted.
                For Each fl In fo.Files
                    Select Case fso.GetExtensionName(fl.Path)
                        Case "bas", "cls", "frm", "frx"
                            fso.DeleteFile (fl)
                    End Select
                Next fl
            End If
        End If
    Loop
    Set cll = Nothing
    
    '~~ Collect all outdated Export-Files in the specified Export-Folder
    Set cll = New Collection
    For Each fl In fso.GetFolder(sExp).Files
        Select Case fso.GetExtensionName(fl.Path)
            Case "bas", "cls", "frm", "frx"
                If Not mComp.Exists(mService.Serviced, fso.GetBaseName(fl)) Then cll.Add fl.Path
        End Select
    Next fl
        
    '~~ Remove all obsolete Export-Files
    With fso
        For Each v In cll
            .DeleteFile v
            Log.Entry = "Export-File obsolete (deleted because component no longer exists)"
        Next v
    End With
    
xt: Set cll = Nothing
    Set fso = Nothing
    Set fo = Nothing
    Set fosub = Nothing
    Set fl = Nothing
    Exit Sub

eh: Select Case mErH.ErrMsg(ErrSrc(PROC))
        Case mErH.DebugOptResumeErrorLine: Stop: Resume
        Case mErH.DebugOptResumeNext: Resume Next
        Case mErH.ErrMsgDefaultButton: End
    End Select
End Sub

