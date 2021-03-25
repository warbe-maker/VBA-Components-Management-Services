Attribute VB_Name = "mCompMan"
Option Explicit
Option Compare Text
' ----------------------------------------------------------------------------
' Standard Module mCompMan
'          Services for the management of VBComponents in Workbooks provided:
'          - stored within the 'ServicedRoot'
'          - have the Conditional Compile Argument 'CompMan = 1'
'          - have 'CompMan' referenced
'          - the Workbook resides in its own dedicated folder
'          - the Workbook calls the '' service with the Open event
'          - the Workbook calls the '' service with the Save event
' Usage:   This Workbbok's services are available as 'CompMan-AddIn' when
'          - at least once the Renew service had been performed
'          - either a Workbbook referring to the Addin is opened
'          - or the Addin-Workbook-Development-Instance is opened and Renew
'            is performed again
'
'          For further detailed information see:
' https://warbe-maker.github.io/warbe-maker.github.io/vba/excel/code/component/management/2021/03/02/Programatically-updating-Excel-VBA-code.html
' ----------------------------------------------------------------------------
' Services:
' - DisplayCodeChange       Displays the current difference between a
'                           component's code and its current Export-File
' - ExportAll               Exports all components into the Workbook's
'                           dedicated folder (created when not existing)
' - ExportChangedComponents Exports all components of which the code in the
'                           Export-File differs from the current code.
' - Service
'
' Uses Common Components: - mBasic
'                         - mErrhndlr
'                         - mFile
'                         - mWrkbk
' Requires:
' - Reference to: - "Microsoft Visual Basic for Applications Extensibility ..."
'                 - "Microsoft Scripting Runtime"
'                 - "Windows Script Host Object Model"
'                 - Trust in the VBA project object modell (Security
'                   setting for makros)
'
' W. Rauschenberger Berlin August 2019
' -------------------------------------------------------------------------------
Public Const MAX_LEN_TYPE                       As Long = 17
Public Const VB_SOURCE_PROJECT                     As String = "VB-Raw-Project"
Public Const VB_TARGET_PROJECT_OF_SOURCE_PROJECT    As String = "VB-Clone-Project of Raw-Project: "

Public Enum enKindOfComp                ' The kind of Component in the sense of CompMan
        enUnknown = 0
        enHostedRaw = 1
        enRawClone = 2                 ' The Component is a used raw, i.e. the raw is hosted by another Workbook
        enInternal = 3             ' Neither a hosted nor a used Raw Common Component
End Enum

Public Enum enUpdateReply
    enUpdateOriginWithUsed
    enUpdateUsedWithOrigin
    enUpdateNone
End Enum

' Distinguish the code of which Workbook is allowed to be updated
Public Enum vbcmType
    vbext_ct_StdModule = 1          ' .bas
    vbext_ct_ClassModule = 2        ' .cls
    vbext_ct_MSForm = 3             ' .frm
    vbext_ct_ActiveXDesigner = 11   ' ??
    vbext_ct_Document = 100         ' .cls
End Enum

Public Enum siCounter
    sic_clone_changed
    sic_clone_comps
    sic_cols_new
    sic_cols_obsolete
    sic_comps
    sic_comps_changed
    sic_comps_total
    sic_named_ranges
    sic_named_ranges_total
    sic_names_new
    sic_names_obsolete
    sic_names_total
    sic_non_doc_mods_code
    sic_non_doc_mod_new
    sic_non_doc_mod_obsolete
    sic_non_doc_mod_total
    sic_oobs_new
    sic_oobs_obsolete
    sic_oobs_total
    sic_raw_changed
    sic_clones_comps_updated
    sic_refs_new
    sic_refs_obsolete
    sic_refs_total
    sic_rows_new
    sic_rows_obsolete
    sic_shapes_new
    sic_shapes_obsolete
    sic_shapes_total
    sic_shape_properties
    sic_sheets_code
    sic_sheets_codename
    sic_sheets_name
    sic_sheets_new
    sic_sheets_obsolete
    sic_sheets_total
End Enum

Public cComp            As clsComp
Public cRaw             As clsRaw
Public asNoSynch()      As String
Public lMaxCompLength   As Long
Public dctHostedRaws    As Dictionary
Public Stats            As clsStats
Private lMaxLenComp     As Long
Private lMaxLenTypeItem As Long

Public Property Get MaxLenComp(Optional ByRef wb As Workbook = Nothing) As Long
    
    Dim vbc     As VBComponent
    Dim lMax    As Long
    
    If Not wb Is Nothing Then
        For Each vbc In wb.VBProject.VBComponents
            lMax = mBasic.Max(lMax, Len(vbc.Name))
        Next vbc
    End If
    lMaxLenComp = Max(lMax, lMaxLenComp)
    MaxLenComp = lMaxLenComp
End Property

Public Property Get MaxLenTypeItem(Optional ByRef wb As Workbook) As Long
    If Not wb Is Nothing Then
        lMaxLenTypeItem = MAX_LEN_TYPE + MaxLenComp(wb)
    End If
    MaxLenTypeItem = lMaxLenTypeItem
End Property
    
Public Function IsSheetComp( _
                      ByRef vbc As VBComponent, _
             Optional ByRef wb As Workbook = Nothing, _
             Optional ByRef sh_name As String = vbNullString) As Boolean
' -----------------------------------------------------------------------
' Returns TRUE when the Component (vbc) represents a Worksheet. When the
' optional Workbook (wb) is provided, the sheet's Name is returned
' (sh_name).
' ------------------------------------------------------------------------
    Dim ws As Worksheet
    
    IsSheetComp = vbc.Type = vbext_ct_Document And Not IsWrkbkComp(vbc)
    If Not wb Is Nothing Then
        For Each ws In wb.Worksheets
            If ws.CodeName = vbc.Name Then
                sh_name = ws.Name
                Exit For
            End If
        Next ws
    End If
End Function

Public Function IsWrkbkComp(ByRef vbc As VBComponent) As Boolean
    
    Dim bSigned As Boolean
    On Error Resume Next
    bSigned = vbc.Properties("VBASigned").Value
    IsWrkbkComp = Err.Number = 0
    
End Function

Private Property Get HostedRaws() As Variant:           Set HostedRaws = dctHostedRaws:                 End Property

Private Property Let HostedRaws(ByVal hr As Variant)
' ---------------------------------------------------
' Saves the names of the hosted raw components (hr)
' to the Dictionary (dctHostedRaws).
' ---------------------------------------------------
    Dim v       As Variant
    Dim sComp   As String
    
    If dctHostedRaws Is Nothing Then
        Set dctHostedRaws = New Dictionary
    Else
        dctHostedRaws.RemoveAll
    End If
    For Each v In Split(hr, ",")
        sComp = Trim$(v)
        If Not dctHostedRaws.Exists(sComp) Then
            dctHostedRaws.Add sComp, sComp
        End If
    Next v
    
End Property

'Public Property Get Service() As String:            Service = sService:             End Property
'
'Public Property Let Service(ByVal srvc As String):  sService = srvc:                End Property

Public Sub CompareCloneWithRaw(ByVal cmp_comp_name As String)
' -----------------------------------------------------------
'
' -----------------------------------------------------------
    Const PROC = "CompareCloneWithRaw"
    
    On Error GoTo eh
    Dim sExpFileRaw As String
    Dim wb          As Workbook
    Dim cComp       As New clsComp
    
    Set wb = ActiveWorkbook
    With cComp
        Set .Wrkbk = wb
        .CompName = cmp_comp_name
        Set .VBComp = wb.VBProject.VBComponents(.CompName)
        sExpFileRaw = mHostedRaws.ExpFileFullName(cmp_comp_name)
    
        mFile.Compare fc_file_left:=.ExpFileFullName _
                    , fc_file_right:=sExpFileRaw _
                    , fc_left_title:="The cloned raw's current code in Workbook/VBProject " & cComp.WrkbkBaseName & " (" & .ExpFileFullName & ")" _
                    , fc_right_title:="The remote raw's current code in Workbook/VBProject " & mBasic.BaseName(mHostedRaws.HostFullName(.CompName)) & " (" & sExpFileRaw & ")"

    End With
    Set cComp = Nothing

xt: Exit Sub

eh: Select Case mErH.ErrMsg(ErrSrc(PROC))
        Case mErH.DebugOptResumeErrorLine: Stop: Resume
        Case mErH.DebugOptResumeNext: Resume Next
        Case mErH.ErrMsgDefaultButton: End
    End Select
End Sub

Public Function CompExists( _
                     ByRef ce_wb As Workbook, _
                     ByVal ce_comp_name As String) As Boolean
' -----------------------------------------------------------
' Returns TRUE when the component (ce_comp_name) exists in
' the Workbook (ce_wb).
' -----------------------------------------------------------
    Dim s As String
    On Error Resume Next
    s = ce_wb.VBProject.VBComponents(ce_comp_name).Name
    CompExists = Err.Number = 0
End Function

Public Sub DeleteObsoleteExpFiles(ByRef do_wb As Workbook)
' --------------------------------------------------------------
' Delete Export Files the component does not or no longer exist.
' --------------------------------------------------------------
    Const PROC = "DeleteObsoleteExpFiles"
    
    On Error GoTo eh
    Dim cll     As New Collection
    Dim fso     As New FileSystemObject
    Dim fl      As File
    Dim v       As Variant
       
    '~~ Collect obsolete Export Files
    For Each fl In fso.GetFolder(do_wb.Path).Files
        Select Case fso.GetExtensionName(fl.Path)
            Case "bas", "cls", "frm", "frx"
                If Not mCompMan.CompExists(do_wb, fso.GetBaseName(fl.Path)) _
                Then cll.Add fl.Path
        End Select
    Next fl
    
    With fso
        For Each v In cll
            .DeleteFile v
            cLog.Entry = "Export-File obsolete (deleted because component no longer exists)"
        Next v
    End With
    
xt: Set cll = Nothing
    Set fso = Nothing
    Exit Sub

eh: Select Case mErH.ErrMsg(ErrSrc(PROC))
        Case mErH.DebugOptResumeErrorLine: Stop: Resume
        Case mErH.DebugOptResumeNext: Resume Next
        Case mErH.ErrMsgDefaultButton: End
    End Select
End Sub

Public Sub DisplayCodeChange(ByVal cmp_comp_name As String)
' -----------------------------------------------------------
'
' -----------------------------------------------------------
    Const PROC = "DisplayCodeChange"
    
    On Error GoTo eh
    Dim sTempExpFileFullName    As String
    Dim wb                      As Workbook
    Dim cComp                   As New clsComp
    Dim fso                     As New FileSystemObject
    Dim sTmpFolder              As String
    Dim flExpTemp               As File
    
    Set wb = ActiveWorkbook
    With cComp
        Set .Wrkbk = wb
        .CompName = cmp_comp_name
        Set .VBComp = wb.VBProject.VBComponents(.CompName)
    End With
    
    With fso
        sTmpFolder = cComp.ExpFilePath & "\Temp"
        If Not .FolderExists(sTmpFolder) Then .CreateFolder sTmpFolder
        sTempExpFileFullName = sTmpFolder & "\" & cComp.CompName & cComp.ExpFileExt
        cComp.VBComp.Export sTempExpFileFullName
        Set flExpTemp = .GetFile(sTempExpFileFullName)
    End With

    With cComp
        mFile.Compare fc_file_left:=sTempExpFileFullName _
                    , fc_file_right:=.ExpFileFullName _
                    , fc_left_title:="The component's current code in Workbook/VBProject " & cComp.WrkbkBaseName & " ('" & sTempExpFileFullName & "')" _
                    , fc_right_title:="The component's currently exported code in '" & .ExpFileFullName & "'"

    End With
    
xt: If fso.FolderExists(sTmpFolder) Then fso.DeleteFolder (sTmpFolder)
    Set cComp = Nothing
    Set fso = Nothing
    Exit Sub

eh: Select Case mErH.ErrMsg(ErrSrc(PROC))
        Case mErH.DebugOptResumeErrorLine: Stop: Resume
        Case mErH.DebugOptResumeNext: Resume Next
        Case mErH.ErrMsgDefaultButton: GoTo xt
    End Select
End Sub

Private Function ErrSrc(ByVal es_proc As String) As String
    ErrSrc = "mCompMan" & "." & es_proc
End Function

Public Sub ExportAll(Optional ByRef exp_wrkbk As Workbook = Nothing)
' -----------------------------------------------------------
'
' -----------------------------------------------------------
    Const PROC = "ExportAll"
    
    On Error GoTo eh
    mErH.BoP ErrSrc(PROC)
    
    mService.ExportAll exp_wrkbk
    
xt: mErH.EoP ErrSrc(PROC)
    Exit Sub
    
eh: mErH.ErrMsg ErrSrc(PROC)
End Sub

Public Sub ExportChangedComponents( _
                             ByRef ec_wb As Workbook, _
                    Optional ByVal ec_hosted As String = vbNullString)
' --------------------------------------------------------------------
' Exclusively performed/trigered by the Before_Save event:
' - Any code change (detected by the comparison of a temporary export
'   file with the current export file) is backed-up/exported
' - Outdated Export Files (components no longer existing) are removed
' - Clone code modifications update the raw code when confirmed by the
'   user
' --------------------------------------------------------------------------
    Const PROC = "ExportChangedComponents"
    
    On Error GoTo eh
'    Dim sExported           As String
'    Dim bUpdated            As Boolean
'    Dim lUpdated            As Long
'    Dim sUpdated            As String
'    Dim sMsg                As String
'    Dim fso                 As New FileSystemObject
'    Dim sProgressDots       As String
'    Dim sStatus             As String
    
    mErH.BoP ErrSrc(PROC)
    mService.ExportChangedComponents ec_wb:=ec_wb, ec_hosted:=ec_hosted
    
xt: mErH.EoP ErrSrc(PROC)   ' End of Procedure (error call stack and execution trace)
    Exit Sub
    
eh: Select Case mErH.ErrMsg(ErrSrc(PROC))
        Case mErH.DebugOptResumeErrorLine: Stop: Resume
        Case mErH.DebugOptResumeNext: Resume Next
        Case mErH.ErrMsgDefaultButton: End
    End Select
End Sub

Public Function ManageVbProjectProperties( _
                                    ByVal mh_hosted As String, _
                                    ByRef mh_wb As Workbook) As Boolean
' ---------------------------------------------------------------------
' - Registers a Workbook as raw host when it has at least one of the
'   Workbook's (mh_wb) components indicated hosted
' - Registers a Workbook as Sync-Source-VB-Project when mh_hosted not indicates
'   a component but = VB_SOURCE_PROJECT
' - Returns FALSE when the VbProjectProperties are invalid!
' ---------------------------------------------------------------------
    Const PROC = "ManageVbProjectProperties"
    
    On Error GoTo eh
    Dim v               As Variant
    Dim fso             As New FileSystemObject
    Dim cComp           As clsComp
    Dim sHosted         As String
    Dim sHostBaseName   As String
    
    mErH.BoP ErrSrc(PROC)
    sHostBaseName = fso.GetBaseName(mh_wb.FullName)
    Set dctHostedRaws = New Dictionary
    HostedRaws = mh_hosted
    
    If HostedRaws.Count = 1 Then
        sHosted = HostedRaws.Keys()(0)
        If IsVBCloneProject(sHosted) Or IsVBRawProject(sHosted) Then
            If IsVBCloneProject(sHosted) Then
                '~~ The Workbook is indicated a VB-Clone-Project of a certain VB-Raw-Project
                If mRawHosts.Exists(sHostBaseName) And mRawHosts.FullName(sHostBaseName) <> mh_wb.FullName Then
                    '~~ The Workbook/VB-Project is known/registered as VB-Raw-Project in another folder under the
                    '~~ same name which confuses it with the VB-Clone-Project unless they are named differently
                    If mMsg.Box(msg_title:="VB-Clone-Project confused with VB-Raw-Project" _
                              , msg:="The name of the VB-Clone-Project(Workbook) is identical with the VB-Raw-Project(Workbook)!" & vbLf & _
                                     "The Workbook name '" & sHostBaseName & "' is already registered as VB-Raw-Project located in '" & _
                                     mRawHosts.FullName(sHostBaseName) & "'. Reply ' Y e s ' when the VB-Raw-Project had been moved to another location " & _
                                     "or the location/folder had been renamed, reply ' N o ' otherwise. The service will be terminated and the name of either " & _
                                     "of the two VB-Projects(Workbooks) must be changed." _
                              , msg_buttons:=vbYesNo) = vbYes _
                    Then
                        mRawHosts.FullName(sHostBaseName) = mh_wb.FullName
                        mRawHosts.IsRawVbProject(sHostBaseName) = True
                        cLog.Entry = "Location of VB-Raw-Project changed."
                        cLog.Entry = "Service is terminated! The identical names for the VB-Clone-Project/Workbook and the VB-Raw-Project still confuses the CompMan services"
                        cLog.Entry = "The VB-Clone-Project perferably should be given another name!"
                    Else
                        cLog.Entry = "VB-Clone-Project name confused with VB-Raw-Project name."
                        cLog.Entry = "Service is terminated, either of the two must be renamed and the service restarted."
                    End If
                    GoTo xt
                End If
                HostedRaws.RemoveAll
                cLog.Entry = "Workbook recognized as VB-Clone-Project of the VB-Raw-Project '" & VBA.Trim$(Split(sHosted, ":")(1)) & "'"
                ManageVbProjectProperties = True
            
            ElseIf IsVBRawProject(sHosted) Then
                '~~ The VB-Project has identified itself as VB-Raw-Project
                mRawHosts.IsRawVbProject(sHostBaseName) = True
                If mRawHosts.FullName(sHostBaseName) <> mh_wb.FullName Then
                    mRawHosts.FullName(sHostBaseName) = mh_wb.FullName
                    cLog.Entry = "Workbook (re)registered as VB-Raw-Project located in '" & mh_wb.Path & "'"
                End If
                ManageVbProjectProperties = True
            End If
            GoTo xt
        End If
    End If
                
    If HostedRaws.Count <> 0 Then
        For Each v In HostedRaws
            '~~ Keep a record for each of the raw components hosted by this Workbook
            If Not mHostedRaws.Exists(raw_comp_name:=v) _
            Or mHostedRaws.HostFullName(comp_name:=v) <> mh_wb.FullName Then
                mHostedRaws.HostFullName(comp_name:=v) = mh_wb.FullName
                cLog.Entry = "Raw-Component '" & v & "' hosted in this Workbook registered"
            End If
            If mHostedRaws.ExpFileFullName(v) = vbNullString Then
                '~~ The component apparently had never been exported before
                Set cComp = New clsComp
                With cComp
                    Set .Wrkbk = mh_wb
                    .CompName = v
                    If Not fso.FileExists(.ExpFileFullName) Then .VBComp.Export .ExpFileFullName
                    mHostedRaws.ExpFileFullName(v) = .ExpFileFullName
                End With
            End If
        Next v
    Else
        '~~ Remove any raws still existing and pointing to this Workbook as host
        For Each v In mHostedRaws.Components
            If mHostedRaws.HostFullName(comp_name:=v) = mh_wb.FullName Then
                mHostedRaws.Remove comp_name:=v
                cLog.Entry = "Component removed from '" & mRawHosts.DAT_FILE & "'"
            End If
        Next v
        If mRawHosts.Exists(fso.GetBaseName(mh_wb.FullName)) Then
            mRawHosts.Remove (fso.GetBaseName(mh_wb.FullName))
            cLog.Entry = "Workbook no longer a host for at least one raw component removed from '" & mRawHosts.DAT_FILE & "'"
        End If
    End If
    ManageVbProjectProperties = True

xt: Set fso = Nothing
    mErH.EoP ErrSrc(PROC)
    Exit Function

eh: Select Case mErH.ErrMsg(ErrSrc(PROC))
        Case mErH.DebugOptResumeErrorLine: Stop: Resume
        Case mErH.DebugOptResumeNext: Resume Next
        Case mErH.ErrMsgDefaultButton: End
    End Select
End Function

Private Function IsVBCloneProject(ByVal s As String) As Boolean
    IsVBCloneProject = InStr(s, mCompMan.VB_TARGET_PROJECT_OF_SOURCE_PROJECT) <> 0
End Function

Private Function IsVBRawProject(ByVal s As String) As Boolean
    IsVBRawProject = s = mCompMan.VB_SOURCE_PROJECT
End Function

Public Sub DisplayChanges( _
           Optional ByVal fl_1 As String = vbNullString, _
           Optional ByVal fl_2 As String = vbNullString)
' --------------------------------------------------------
'
' --------------------------------------------------------
    Const PROC = "DisplayChanges"
    
    On Error GoTo eh
    Dim fl_left         As File
    Dim fl_right        As File
    
    If fl_1 = vbNullString _
    Then mFile.SelectFile sel_result:=fl_left, _
                          sel_title:="Select the file regarded 'before the change' (displayed at the left)!"
    
    If fl_2 = vbNullString _
    Then mFile.SelectFile sel_result:=fl_right, _
                          sel_title:="Select the file regarded 'the changed one' (displayed at the right)!"
    
    fl_1 = fl_left.Path
    fl_2 = fl_right.Path
    
    mFile.Compare fc_file_left:=fl_1 _
                , fc_left_title:=fl_1 & " ( b e f o r e  the changes)" _
                , fc_file_right:=fl_2 _
                , fc_right_title:=fl_2 & " ( a f t e r  the changes)"

xt: Exit Sub

eh: Select Case mErH.ErrMsg(ErrSrc(PROC))
        Case mErH.DebugOptResumeErrorLine: Stop: Resume
        Case mErH.DebugOptResumeNext: Resume Next
        Case mErH.ErrMsgDefaultButton: End
    End Select
End Sub

Public Function TypeString(ByVal vbc As VBComponent) As String
    Select Case vbc.Type
        Case vbext_ct_ActiveXDesigner:  TypeString = "ActiveX-Designer"
        Case vbext_ct_ClassModule:      TypeString = "Class-Module"
        Case vbext_ct_Document
            If mCompMan.IsSheetComp(vbc) _
            Then TypeString = "Document-Module (Worksheet)" _
            Else TypeString = "Document-Module (Workbook)"
        Case vbext_ct_MSForm:           TypeString = "UserForm"
        Case vbext_ct_StdModule:        TypeString = "Standatd-Module"
    End Select
End Function

Public Sub DsplyProgress( _
          Optional ByVal p_result As String = vbNullString, _
          Optional ByVal p_total As Long = 0, _
          Optional ByVal p_done As Long = 0)

    Dim sService    As String
    Dim sDots       As String
    Dim sMsg        As String
    
    If p_total - p_done >= 0 Then sDots = VBA.String$(p_total - p_done, ".")
    On Error Resume Next
    sService = cLog.Service
    sMsg = sService & sDots & p_result
    If Len(sMsg) > 250 Then sMsg = Left(sMsg, 246) & "...."
    Application.StatusBar = sMsg

End Sub

Public Sub SynchTargetWbWithSourceWb( _
                               ByRef wb_target As Workbook, _
                               ByVal wb_source As String)
' -------------------------------------------------------------
' Synchronizes the code of the open/ed Workbook (clone_project)
' with the code of the source Workbook (raw_project).
' The service is performed provided:
' - the Workbook is open/ed in the configured "Serviced Root"
' - the CompMan Addin is not paused
' - the open/ed Workbook is not a restored version
' -------------------------------------------------------------
    Const PROC = "SynchTargetWbWithSourceWb"
    
    On Error GoTo eh
    mErH.BoP ErrSrc(PROC)
    mService.SyncTargetWithSource wb_target:=wb_target, wb_source_name:=wb_source
    
xt: mErH.EoP ErrSrc(PROC)
    Set cLog = Nothing
    Exit Sub

eh: Select Case mErH.ErrMsg(ErrSrc(PROC))
        Case mErH.DebugOptResumeErrorLine: Stop: Resume
        Case mErH.DebugOptResumeNext: Resume Next
        Case mErH.ErrMsgDefaultButton: GoTo xt
    End Select
End Sub

Public Sub UpdateRawClones( _
                     ByRef uc_wb As Workbook, _
            Optional ByVal uc_hosted As String = vbNullString)
' ------------------------------------------------------------
' Updates a clone component with the Export-File of the remote
' raw component provided the raw's code has changed.
' ------------------------------------------------------------
    Const PROC = "UpdateRawClones"
    
    On Error GoTo eh
    mErH.BoP ErrSrc(PROC)
    mService.UpdateRawClones uc_wb:=uc_wb, uc_hosted:=uc_hosted
    
xt: mErH.EoP ErrSrc(PROC)
    Exit Sub

eh: Select Case mErH.ErrMsg(ErrSrc(PROC))
        Case mErH.DebugOptResumeErrorLine: Stop: Resume
        Case mErH.DebugOptResumeNext: Resume Next
        Case mErH.ErrMsgDefaultButton: GoTo xt
    End Select
End Sub

Public Function WbkGetOpen(ByVal go_wb_full_name As String) As Workbook
' ---------------------------------------------------------------------
' Returns an opened Workbook object named (go_wb_full_name) or Nothing
' when a file named (go_wb_full_name) not exists.
' ---------------------------------------------------------------------
    Const PROC = "WbkGetOpen"
    
    On Error GoTo eh
    Dim fso As New FileSystemObject
    
    If fso.FileExists(go_wb_full_name) Then
        If mCompMan.WbkIsOpen(io_name:=go_wb_full_name) _
        Then Set WbkGetOpen = Application.Workbooks(go_wb_full_name) _
        Else Set WbkGetOpen = Application.Workbooks.Open(go_wb_full_name)
    End If
    
xt: Set fso = Nothing
    Exit Function
    
eh: Select Case mErH.ErrMsg(ErrSrc(PROC))
        Case mErH.DebugOptResumeErrorLine: Stop: Resume
        Case mErH.DebugOptResumeNext: Resume Next
        Case mErH.ErrMsgDefaultButton: GoTo xt
    End Select
End Function

Public Function WbkIsOpen( _
           Optional ByVal io_name As String = vbNullString, _
           Optional ByVal io_full_name As String) As Boolean
' ------------------------------------------------------------
' When the full name is provided the check spans all Excel
' instances else only the current one.
' ------------------------------------------------------------
    Const PROC = ""
    
    On Error GoTo eh
    Dim fso     As New FileSystemObject
    Dim xlApp   As Excel.Application
    
    If io_name = vbNullString And io_full_name = vbNullString Then GoTo xt
    
    If io_full_name <> vbNullString Then
        '~~ With the full name the open test spans all application instances
        If Not fso.FileExists(io_full_name) Then GoTo xt
        If io_name = vbNullString Then io_name = fso.GetFileName(io_full_name)
        On Error Resume Next
        Set xlApp = GetObject(io_full_name).Application
        WbkIsOpen = Err.Number = 0
    Else
        On Error Resume Next
        io_name = Application.Workbooks(io_name).Name
        WbkIsOpen = Err.Number = 0
    End If

xt: Exit Function

eh: Select Case mErH.ErrMsg(ErrSrc(PROC))
        Case mErH.DebugOptResumeErrorLine: Stop: Resume
        Case mErH.DebugOptResumeNext: Resume Next
        Case mErH.ErrMsgDefaultButton: GoTo xt
    End Select
End Function

Public Function WinMergeIsInstalled() As Boolean
    WinMergeIsInstalled = AppIsInstalled("WinMerge")
End Function
