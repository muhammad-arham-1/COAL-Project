TITLE UndeleteX - FAT12 Disk Inspector & File Recovery (MASM / Irvine32)

INCLUDE Irvine32.inc

DISK_BUFFER_SIZE    EQU 1474560
ROOT_ENTRY_SIZE     EQU 32
FAT12_EOC_MIN       EQU 0FF8h
FAT12_EOC_MARK      EQU 0FFFh
DELETED_MARKER      EQU 0E5h
EMPTY_ENTRY_MARKER  EQU 000h

.data
    promptImgName   BYTE "Enter FAT12 disk image filename (e.g., disk.img): ", 0
    promptMenu      BYTE 0Dh, 0Ah, "================ UndeleteX Menu ================", 0Dh, 0Ah
                    BYTE "1. Disk & Boot Sector Info", 0Dh, 0Ah
                    BYTE "2. List Root Directory Files", 0Dh, 0Ah
                    BYTE "3. View Cluster Chain of a File", 0Dh, 0Ah
                    BYTE "4. Hex Dump of a File", 0Dh, 0Ah
                    BYTE "5. Recover Deleted File (Patch Image + Extract)", 0Dh, 0Ah
                    BYTE "6. Save Patched Disk Image to File", 0Dh, 0Ah
                    BYTE "0. Exit", 0Dh, 0Ah
                    BYTE "Select option: ", 0

    msgLoadOk       BYTE "Disk image loaded successfully. Bytes read: ", 0
    msgLoadErr      BYTE "Error: Could not open or read disk image!", 0Dh, 0Ah, 0
    msgBadChoice    BYTE "Invalid choice. Try again.", 0Dh, 0Ah, 0
    msgBye          BYTE "Exiting UndeleteX.", 0Dh, 0Ah, 0

    hdrBoot         BYTE 0Dh, 0Ah, "--- Boot Sector & Layout ---", 0Dh, 0Ah, 0
    lblBytesSec     BYTE "Bytes / Sector      : ", 0
    lblSecClus      BYTE "Sectors / Cluster   : ", 0
    lblResSec       BYTE "Reserved Sectors    : ", 0
    lblNumFATs      BYTE "Number of FATs      : ", 0
    lblRootEnt      BYTE "Root Dir Entries    : ", 0
    lblSecFAT       BYTE "Sectors / FAT       : ", 0
    lblFatStart     BYTE "FAT1 Byte Offset    : ", 0
    lblRootStart    BYTE "Root Dir Byte Offset: ", 0
    lblDataStart    BYTE "Data Area Offset    : ", 0

    hdrDir          BYTE 0Dh, 0Ah, "Idx | Status    | Name (8.3)  | Attr | StartClus | Size(B)", 0Dh, 0Ah
                    BYTE "----+-----------+-------------+------+-----------+--------", 0Dh, 0Ah, 0
    strDeleted      BYTE "[DELETED] ", 0
    strActive       BYTE "[ACTIVE]  ", 0
    strEndDir       BYTE "(End of root directory entries reached)", 0Dh, 0Ah, 0
    promptEntryIdx  BYTE "Enter directory entry index (Idx): ", 0
    msgBadIdx       BYTE "Invalid entry index.", 0Dh, 0Ah, 0
    msgDirEmptyClus BYTE "Entry has starting cluster 0 (empty file or volume entry).", 0Dh, 0Ah, 0

    hdrChain        BYTE 0Dh, 0Ah, "Cluster Chain: ", 0
    strArrow        BYTE " -> ", 0
    strEOC          BYTE " [EOC]", 0Dh, 0Ah, 0
    strBroken       BYTE " [ZERO/FREE - Chain broken]", 0Dh, 0Ah, 0
    hdrHex          BYTE 0Dh, 0Ah, "--- Hex Dump ---", 0Dh, 0Ah, 0
    msgHexLimitNote BYTE "(Showing first 1024 bytes max for readability)", 0Dh, 0Ah, 0

    msgNotDeleted   BYTE "Selected entry is NOT marked deleted (0xE5).", 0Dh, 0Ah, 0
    msgZeroSize     BYTE "Warning: File size is 0 bytes. Restoring name only.", 0Dh, 0Ah, 0
    promptFirstChar BYTE "Enter the missing first character (ASCII): ", 0
    msgRecovDone    BYTE "Entry restored in memory! Clusters linked: ", 0
    promptExtractFn BYTE "Enter output filename for recovered file (e.g., recovered.txt): ", 0
    promptSaveImgFn BYTE "Enter output filename for patched disk image (e.g., fixed.img): ", 0
    msgWriteOk      BYTE "File written successfully.", 0Dh, 0Ah, 0
    msgWriteErr     BYTE "Error writing output file!", 0Dh, 0Ah, 0
    msgRecovNote    BYTE "Note: Contiguous clusters assumed from start cluster; both FAT copies updated.", 0Dh, 0Ah, 0

    bytesPerSector  DWORD 512
    sectorsPerClus  DWORD 1
    reservedSectors DWORD 1
    numFATs         DWORD 2
    rootEntries     DWORD 224
    sectorsPerFAT   DWORD 9

    fatStart        DWORD 512
    fatSizeBytes    DWORD 4608
    rootStart       DWORD 9728
    rootSizeBytes   DWORD 7168
    dataStart       DWORD 16896
    clusterSize     DWORD 512

    bytesLoaded     DWORD 0
    fileHandle      HANDLE ?
    imgFilename     BYTE 128 DUP(0)
    outFilename     BYTE 128 DUP(0)
    nameBuf         BYTE 13 DUP(0)

.data?
    diskBuf         BYTE DISK_BUFFER_SIZE DUP(?)
    extractBuf      BYTE 65536 DUP(?)

.code

main PROC
    mov edx, OFFSET promptImgName
    call WriteString
    mov edx, OFFSET imgFilename
    mov ecx, SIZEOF imgFilename - 1
    call ReadString
    cmp eax, 0
    je exit_prog

    call LoadDiskImage
    jc exit_prog

    call ParseBootSector

menu_loop:
    mov edx, OFFSET promptMenu
    call WriteString
    call ReadInt

    cmp eax, 1
    je opt_info
    cmp eax, 2
    je opt_list
    cmp eax, 3
    je opt_chain
    cmp eax, 4
    je opt_hexdump
    cmp eax, 5
    je opt_recover
    cmp eax, 6
    je opt_save_img
    cmp eax, 0
    je opt_exit

    mov edx, OFFSET msgBadChoice
    call WriteString
    jmp menu_loop

opt_info:
    call ShowBootInfo
    jmp menu_loop

opt_list:
    call ListRootDirectory
    jmp menu_loop

opt_chain:
    call ViewFileClusterChain
    jmp menu_loop

opt_hexdump:
    call HexDumpFile
    jmp menu_loop

opt_recover:
    call RecoverDeletedFile
    jmp menu_loop

opt_save_img:
    mov edx, OFFSET promptSaveImgFn
    call WriteString
    mov edx, OFFSET outFilename
    mov ecx, SIZEOF outFilename - 1
    call ReadString
    mov edx, OFFSET outFilename
    mov esi, OFFSET diskBuf
    mov ecx, bytesLoaded
    call WriteBufferToFile
    jmp menu_loop

opt_exit:
    mov edx, OFFSET msgBye
    call WriteString

exit_prog:
    exit
main ENDP

LoadDiskImage PROC
    mov edx, OFFSET imgFilename
    call OpenInputFile
    cmp eax, INVALID_HANDLE_VALUE
    je load_fail

    mov fileHandle, eax
    mov edx, OFFSET diskBuf
    mov ecx, DISK_BUFFER_SIZE
    call ReadFromFile
    jc load_close_fail

    mov bytesLoaded, eax
    mov eax, fileHandle
    call CloseHandle

    mov edx, OFFSET msgLoadOk
    call WriteString
    mov eax, bytesLoaded
    call WriteDec
    call Crlf
    clc
    ret

load_close_fail:
    mov eax, fileHandle
    call CloseHandle
load_fail:
    mov edx, OFFSET msgLoadErr
    call WriteString
    stc
    ret
LoadDiskImage ENDP

ParseBootSector PROC
    mov esi, OFFSET diskBuf

    movzx eax, WORD PTR [esi + 11]
    cmp eax, 0
    jne bps_ok
    mov eax, 512
bps_ok:
    mov bytesPerSector, eax

    movzx eax, BYTE PTR [esi + 13]
    cmp eax, 0
    jne spc_ok
    mov eax, 1
spc_ok:
    mov sectorsPerClus, eax

    movzx eax, WORD PTR [esi + 14]
    mov reservedSectors, eax

    movzx eax, BYTE PTR [esi + 16]
    mov numFATs, eax

    movzx eax, WORD PTR [esi + 17]
    mov rootEntries, eax

    movzx eax, WORD PTR [esi + 22]
    mov sectorsPerFAT, eax

    mov eax, reservedSectors
    mul bytesPerSector
    mov fatStart, eax

    mov eax, sectorsPerFAT
    mul bytesPerSector
    mov fatSizeBytes, eax

    mov eax, numFATs
    mul sectorsPerFAT
    add eax, reservedSectors
    mul bytesPerSector
    mov rootStart, eax

    mov eax, rootEntries
    mov ebx, ROOT_ENTRY_SIZE
    mul ebx
    mov rootSizeBytes, eax

    mov eax, rootStart
    add eax, rootSizeBytes
    mov dataStart, eax

    mov eax, sectorsPerClus
    mul bytesPerSector
    mov clusterSize, eax
    ret
ParseBootSector ENDP

ShowBootInfo PROC
    mov edx, OFFSET hdrBoot
    call WriteString

    mov edx, OFFSET lblBytesSec
    call WriteString
    mov eax, bytesPerSector
    call WriteDec
    call Crlf

    mov edx, OFFSET lblSecClus
    call WriteString
    mov eax, sectorsPerClus
    call WriteDec
    call Crlf

    mov edx, OFFSET lblResSec
    call WriteString
    mov eax, reservedSectors
    call WriteDec
    call Crlf

    mov edx, OFFSET lblNumFATs
    call WriteString
    mov eax, numFATs
    call WriteDec
    call Crlf

    mov edx, OFFSET lblRootEnt
    call WriteString
    mov eax, rootEntries
    call WriteDec
    call Crlf

    mov edx, OFFSET lblSecFAT
    call WriteString
    mov eax, sectorsPerFAT
    call WriteDec
    call Crlf

    mov edx, OFFSET lblFatStart
    call WriteString
    mov eax, fatStart
    call WriteDec
    call Crlf

    mov edx, OFFSET lblRootStart
    call WriteString
    mov eax, rootStart
    call WriteDec
    call Crlf

    mov edx, OFFSET lblDataStart
    call WriteString
    mov eax, dataStart
    call WriteDec
    call Crlf
    ret
ShowBootInfo ENDP

GetRootEntryPtr PROC
    mov ebx, ROOT_ENTRY_SIZE
    mul ebx
    mov esi, OFFSET diskBuf
    add esi, rootStart
    add esi, eax
    ret
GetRootEntryPtr ENDP

Format83Name PROC
    push eax
    push ecx
    push esi
    push edi

    mov ecx, 8
copy_base:
    mov al, [esi]
    cmp al, ' '
    je skip_base_char
    mov [edi], al
    inc edi
skip_base_char:
    inc esi
    loop copy_base

    mov al, [esi]
    cmp al, ' '
    jne has_ext
    mov al, [esi + 1]
    cmp al, ' '
    jne has_ext
    mov al, [esi + 2]
    cmp al, ' '
    jne has_ext
    jmp done_name

has_ext:
    mov BYTE PTR [edi], '.'
    inc edi
    mov ecx, 3
copy_ext:
    mov al, [esi]
    cmp al, ' '
    je skip_ext_char
    mov [edi], al
    inc edi
skip_ext_char:
    inc esi
    loop copy_ext

done_name:
    mov BYTE PTR [edi], 0

    pop edi
    pop esi
    pop ecx
    pop eax
    ret
Format83Name ENDP

ListRootDirectory PROC
    mov edx, OFFSET hdrDir
    call WriteString

    xor ecx, ecx
dir_loop:
    cmp ecx, rootEntries
    jae dir_done

    mov eax, ecx
    call GetRootEntryPtr

    movzx eax, BYTE PTR [esi]
    cmp al, EMPTY_ENTRY_MARKER
    je dir_end_marker

    mov eax, ecx
    call WriteDec
    mov al, ' '
    call WriteChar
    mov al, '|'
    call WriteChar
    mov al, ' '
    call WriteChar

    mov al, [esi]
    cmp al, DELETED_MARKER
    je print_del

    mov eax, lightGray + (black * 16)
    call SetTextColor
    mov edx, OFFSET strActive
    call WriteString
    jmp after_status

print_del:
    mov eax, lightRed + (black * 16)
    call SetTextColor
    mov edx, OFFSET strDeleted
    call WriteString

after_status:
    mov eax, lightGray + (black * 16)
    call SetTextColor

    mov al, '|'
    call WriteChar
    mov al, ' '
    call WriteChar

    mov edi, OFFSET nameBuf
    call Format83Name
    mov edx, OFFSET nameBuf
    call WriteString

    mov edx, OFFSET nameBuf
    call StrLength
    mov ebx, 12
    sub ebx, eax
    jle no_pad
pad_loop:
    mov al, ' '
    call WriteChar
    dec ebx
    jnz pad_loop
no_pad:

    mov al, '|'
    call WriteChar
    mov al, ' '
    call WriteChar

    movzx eax, BYTE PTR [esi + 11]
    call WriteHex
    mov edx, OFFSET strArrow
    mov al, ' '
    call WriteChar
    mov al, '|'
    call WriteChar
    mov al, ' '
    call WriteChar

    movzx eax, WORD PTR [esi + 26]
    call WriteDec

    mov edx, OFFSET nameBuf
    mov al, ' '
    call WriteChar
    call WriteChar
    mov al, '|'
    call WriteChar
    mov al, ' '
    call WriteChar

    mov eax, DWORD PTR [esi + 28]
    call WriteDec
    call Crlf

    inc ecx
    jmp dir_loop

dir_end_marker:
    mov edx, OFFSET strEndDir
    call WriteString

dir_done:
    ret
ListRootDirectory ENDP

ReadFAT12Entry PROC
    push ebx
    push ecx
    push esi

    mov ebx, ecx
    shr ebx, 1
    add ebx, ecx

    mov esi, OFFSET diskBuf
    add esi, fatStart
    add esi, ebx

    movzx eax, WORD PTR [esi]

    test ecx, 1
    jnz odd_cluster

    and eax, 0FFFh
    jmp done_read_fat

odd_cluster:
    shr eax, 4

done_read_fat:
    pop esi
    pop ecx
    pop ebx
    ret
ReadFAT12Entry ENDP

WriteFAT12Entry PROC
    push eax
    push ebx
    push edx
    push esi
    push edi

    and dx, 0FFFh

    mov ebx, ecx
    shr ebx, 1
    add ebx, ecx

    mov edi, 2
    mov esi, OFFSET diskBuf
    add esi, fatStart
    add esi, ebx

write_fat_copy:
    movzx eax, WORD PTR [esi]

    test ecx, 1
    jnz write_odd

    and ax, 0F000h
    or ax, dx
    jmp store_fat_word

write_odd:
    and ax, 000Fh
    push dx
    shl dx, 4
    or ax, dx
    pop dx

store_fat_word:
    mov WORD PTR [esi], ax

    add esi, fatSizeBytes
    dec edi
    jnz write_fat_copy

    pop edi
    pop esi
    pop edx
    pop ebx
    pop eax
    ret
WriteFAT12Entry ENDP

ClusterToOffset PROC
    push ebx
    cmp eax, 2
    jb clus_err
    sub eax, 2
    mul clusterSize
    add eax, dataStart
    pop ebx
    ret
clus_err:
    mov eax, dataStart
    pop ebx
    ret
ClusterToOffset ENDP

ViewFileClusterChain PROC
    mov edx, OFFSET promptEntryIdx
    call WriteString
    call ReadInt

    cmp eax, 0
    jl bad_idx
    cmp eax, rootEntries
    jae bad_idx

    call GetRootEntryPtr
    movzx ecx, WORD PTR [esi + 26]
    cmp ecx, 2
    jb zero_clus

    mov edx, OFFSET hdrChain
    call WriteString

    mov ebx, 0
walk_loop:
    mov eax, ecx
    call WriteDec

    call ReadFAT12Entry
    cmp eax, FAT12_EOC_MIN
    jae chain_eoc

    cmp eax, 2
    jb chain_zero

    mov edx, OFFSET strArrow
    call WriteString
    mov ecx, eax
    inc ebx
    cmp ebx, 2880
    jb walk_loop

chain_eoc:
    mov edx, OFFSET strEOC
    call WriteString
    ret

chain_zero:
    mov edx, OFFSET strBroken
    call WriteString
    ret

zero_clus:
    mov edx, OFFSET msgDirEmptyClus
    call WriteString
    ret

bad_idx:
    mov edx, OFFSET msgBadIdx
    call WriteString
    ret
ViewFileClusterChain ENDP

HexDumpFile PROC
    mov edx, OFFSET promptEntryIdx
    call WriteString
    call ReadInt

    cmp eax, 0
    jl hex_bad_idx
    cmp eax, rootEntries
    jae hex_bad_idx

    call GetRootEntryPtr
    movzx eax, WORD PTR [esi + 26]
    cmp eax, 2
    jb hex_zero_clus

    mov ecx, DWORD PTR [esi + 28]
    cmp ecx, 0
    je hex_zero_clus

    cmp ecx, 1024
    jbe size_ok
    mov ecx, 1024
    mov edx, OFFSET msgHexLimitNote
    call WriteString
size_ok:

    call ClusterToOffset
    mov esi, OFFSET diskBuf
    add esi, eax

    mov edx, OFFSET hdrHex
    call WriteString

    xor ebx, ebx
row_loop:
    cmp ebx, ecx
    jae hex_done

    mov eax, ebx
    call WriteHex
    mov al, ':'
    call WriteChar
    mov al, ' '
    call WriteChar

    xor edx, edx
col_loop:
    cmp edx, 16
    jae end_row
    mov eax, ebx
    add eax, edx
    cmp eax, ecx
    jae pad_row

    push esi
    add esi, eax
    movzx eax, BYTE PTR [esi]
    pop esi

    cmp al, 10h
    jae no_lead_zero
    push eax
    mov al, '0'
    call WriteChar
    pop eax
no_lead_zero:
    call WriteHex
    mov al, ' '
    call WriteChar

    inc edx
    jmp col_loop

pad_row:
    mov al, ' '
    call WriteChar
    call WriteChar
    call WriteChar
    inc edx
    jmp col_loop

end_row:
    add ebx, 16
    call Crlf
    jmp row_loop

hex_done:
    ret

hex_bad_idx:
    mov edx, OFFSET msgBadIdx
    call WriteString
    ret

hex_zero_clus:
    mov edx, OFFSET msgDirEmptyClus
    call WriteString
    ret
HexDumpFile ENDP

RecoverDeletedFile PROC
    mov edx, OFFSET promptEntryIdx
    call WriteString
    call ReadInt

    cmp eax, 0
    jl rec_bad_idx
    cmp eax, rootEntries
    jae rec_bad_idx

    call GetRootEntryPtr
    mov al, [esi]
    cmp al, DELETED_MARKER
    jne rec_not_deleted

    mov edx, OFFSET promptFirstChar
    call WriteString
    call ReadChar
    call Crlf
    mov [esi], al

    movzx ecx, WORD PTR [esi + 26]
    mov eax, DWORD PTR [esi + 28]
    mov ebx, eax

    cmp ebx, 0
    jne calc_clusters

    mov edx, OFFSET msgZeroSize
    call WriteString
    jmp done_fat_link

calc_clusters:
    cmp ecx, 2
    jb rec_zero_clus

    mov edx, clusterSize
    dec edx
    add eax, edx
    xor edx, edx
    div clusterSize
    mov edi, eax

link_loop:
    cmp edi, 1
    jbe last_cluster_link

    mov edx, ecx
    inc edx
    call WriteFAT12Entry

    inc ecx
    dec edi
    jmp link_loop

last_cluster_link:
    mov dx, FAT12_EOC_MARK
    call WriteFAT12Entry

done_fat_link:
    mov edx, OFFSET msgRecovDone
    call WriteString
    mov eax, edi
    call WriteDec
    call Crlf
    mov edx, OFFSET msgRecovNote
    call WriteString

    cmp ebx, 0
    je rec_done
    movzx eax, WORD PTR [esi + 26]
    cmp eax, 2
    jb rec_done

    call ClusterToOffset
    push esi
    mov esi, OFFSET diskBuf
    add esi, eax

    mov edi, OFFSET extractBuf
    mov ecx, ebx
    cmp ecx, SIZEOF extractBuf
    jbe copy_ok
    mov ecx, SIZEOF extractBuf
copy_ok:
    push ecx
    rep movsb
    pop ecx
    pop esi

    push ecx
    mov edx, OFFSET promptExtractFn
    call WriteString
    mov edx, OFFSET outFilename
    mov ecx, SIZEOF outFilename - 1
    call ReadString
    pop ecx

    mov edx, OFFSET outFilename
    mov esi, OFFSET extractBuf
    call WriteBufferToFile
    ret

rec_not_deleted:
    mov edx, OFFSET msgNotDeleted
    call WriteString
    ret

rec_bad_idx:
    mov edx, OFFSET msgBadIdx
    call WriteString
    ret

rec_zero_clus:
    mov edx, OFFSET msgDirEmptyClus
    call WriteString
    ret

rec_done:
    ret
RecoverDeletedFile ENDP

WriteBufferToFile PROC
    push ecx
    push esi
    call CreateOutputFile
    pop esi
    pop ecx

    cmp eax, INVALID_HANDLE_VALUE
    je write_fail

    push eax
    mov edx, esi
    call WriteToFile
    jc write_close_fail

    pop eax
    call CloseHandle

    mov edx, OFFSET msgWriteOk
    call WriteString
    ret

write_close_fail:
    pop eax
    call CloseHandle
write_fail:
    mov edx, OFFSET msgWriteErr
    call WriteString
    ret
WriteBufferToFile ENDP

END main
