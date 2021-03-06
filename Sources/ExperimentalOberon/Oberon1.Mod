MODULE Oberon; (*module Oberon for a boot file containing the entire Oberon system / Experimental Oberon / AP 1.7.18*)
  IMPORT SYSTEM, Kernel, Files, Modules, Input, Display, Viewers, Fonts, Texts;

  CONST off = 0; idle = 1; active = 2; (*task states*)
    BasicCycle = 20; ESC = 1BX; SETSTAR = 1AX;

  TYPE Painter* = PROCEDURE (x, y: INTEGER);
    Marker* = RECORD Fade*, Draw*: Painter END;
    
    Cursor* = RECORD
       marker*: Marker; on*: BOOLEAN; X*, Y*: INTEGER
    END;

    InputMsg* = RECORD (Viewers.InputMsg)
      fnt*: Fonts.Font;
      col*, voff*: INTEGER
    END;

    SelectionMsg* = RECORD (Viewers.FrameMsg)
      time*: LONGINT;
      text*: Texts.Text;
      beg*, end*: LONGINT
    END;

    Task* = POINTER TO TaskDesc;

    Handler* = PROCEDURE;

    TaskDesc* = RECORD
      state, nextTime, period*: INTEGER;
      next: Task;
      handle: Handler
    END;

  VAR User*: ARRAY 8 OF CHAR; Password*: LONGINT;
    Arrow*, Star*: Marker; (*predefined markers representing an arrow pointing to the NW and a star symbol*)
    Mouse, Pointer: Cursor; (*predefined cursors representing a mouse and a global system pointer*)

    Log*: Texts.Text;

    Par*: RECORD
      vwr*: Viewers.Viewer;
      frame*: Viewers.Frame;
      text*: Texts.Text;
      pos*: LONGINT
    END;

    CurFnt*: Fonts.Font;
    CurCol*, CurOff*: INTEGER;
    NofTasks*: INTEGER;

    CurTask: Task;
    DW, DH, CL: INTEGER;
    ActCnt: INTEGER; (*action count for GC*)
    Mod: Modules.Module;

    W: Texts.Writer;

  (*user identification*)

  PROCEDURE Code(VAR s: ARRAY OF CHAR): LONGINT;
    VAR i: INTEGER; a, b, c: LONGINT;
  BEGIN
    a := 0; b := 0; i := 0;
    WHILE s[i] # 0X DO
      c := b; b := a; a := (c MOD 509 + 1) * 127 + ORD(s[i]);
      INC(i)
    END;
    IF b >= 32768 THEN b := b - 65536 END;
    RETURN b * 65536 + a
  END Code;

  PROCEDURE SetUser* (VAR user, password: ARRAY OF CHAR);
  BEGIN User := user; Password := Code(password)
  END SetUser;

  PROCEDURE Clock*(): LONGINT;
  BEGIN RETURN Kernel.Clock()
  END Clock;

  PROCEDURE SetClock* (d: LONGINT);
  BEGIN Kernel.SetClock(d)
  END SetClock;

  PROCEDURE Time*(): LONGINT;
  BEGIN RETURN Kernel.Time()
  END Time;

  (*cursors handling*)

  PROCEDURE FlipArrow (X, Y: INTEGER);
  BEGIN
    IF X < CL THEN
      IF X > DW - 15 THEN X := DW - 15 END
    ELSE
      IF X > CL + DW - 15 THEN X := CL + DW - 15 END
    END ;
    IF Y < 14 THEN Y := 14 ELSIF Y > DH THEN Y := DH END ;
    Display.CopyPattern(Display.white, Display.arrow, X, Y - 14, 0, 0, Display.invert)
  END FlipArrow;
     
  PROCEDURE FlipStar (X, Y: INTEGER);
  BEGIN
    IF X < CL THEN
      IF X < 7 THEN X := 7 ELSIF X > DW - 8 THEN X := DW - 8 END
    ELSE
      IF X < CL + 7 THEN X := CL + 7 ELSIF X > CL + DW - 8 THEN X := CL + DW - 8 END
    END ;
    IF Y < 7 THEN Y := 7 ELSIF Y > DH - 8 THEN Y := DH - 8 END ;
    Display.CopyPattern(Display.white, Display.star, X - 7, Y - 7, 0, 0, Display.invert)
  END FlipStar;

  PROCEDURE OpenCursor(VAR c: Cursor);
  BEGIN c.on := FALSE; c.X := 0; c.Y := 0
  END OpenCursor;
 
  PROCEDURE FadeCursor(VAR c: Cursor);
  BEGIN IF c.on THEN c.marker.Fade(c.X, c.Y); c.on := FALSE END
  END FadeCursor;

  PROCEDURE DrawCursor(VAR c: Cursor; m: Marker; x, y: INTEGER);
  BEGIN
    IF c.on & ((x # c.X) OR (y # c.Y) OR (m.Draw # c.marker.Draw)) THEN
      c.marker.Fade(c.X, c.Y); c.on := FALSE
    END;
    IF ~c.on THEN
      m.Draw(x, y); c.marker := m; c.X := x; c.Y := y; c.on := TRUE
    END
  END DrawCursor;

  PROCEDURE DrawMouse*(m: Marker; x, y: INTEGER);
  BEGIN DrawCursor(Mouse, m, x, y)
  END DrawMouse;

  PROCEDURE DrawMouseArrow*(x, y: INTEGER);
  BEGIN DrawCursor(Mouse, Arrow, x, y)
  END DrawMouseArrow;

  PROCEDURE DrawMouseStar* (x, y: INTEGER);
  BEGIN DrawCursor(Mouse, Star, x, y)
  END DrawMouseStar;

  PROCEDURE FadeMouse*;
  BEGIN FadeCursor(Mouse)
  END FadeMouse;

  PROCEDURE MouseOn*(): BOOLEAN;
  BEGIN RETURN Mouse.on
  END MouseOn;

  PROCEDURE DrawPointer*(m: Marker; x, y: INTEGER);
  BEGIN DrawCursor(Pointer, m, x, y)
  END DrawPointer;

  PROCEDURE DrawPointerArrow*(x, y: INTEGER);
  BEGIN DrawCursor(Pointer, Arrow, x, y)
  END DrawPointerArrow;

  PROCEDURE DrawPointerStar*(x, y: INTEGER);
  BEGIN DrawCursor(Pointer, Star, x, y)
  END DrawPointerStar;

  PROCEDURE FadePointer*;
  BEGIN FadeCursor(Pointer)
  END FadePointer;

  PROCEDURE PointerOn*(): BOOLEAN;
  BEGIN RETURN Pointer.on
  END PointerOn;

  PROCEDURE RemoveMarks* (X, Y, W, H: INTEGER);
  BEGIN
    IF (Mouse.X > X - 16) & (Mouse.X < X + W + 16) & (Mouse.Y > Y - 16) & (Mouse.Y < Y + H + 16) THEN
      FadeCursor(Mouse)
    END ;
    IF (Pointer.X > X - 8) & (Pointer.X < X + W + 8) & (Pointer.Y > Y - 8) & (Pointer.Y < Y + H + 8) THEN
      FadeCursor(Pointer)
    END
  END RemoveMarks;

  (*current looks*)

  PROCEDURE SetFont* (fnt: Fonts.Font);
  BEGIN CurFnt := fnt
  END SetFont;

  PROCEDURE SetColor* (col: INTEGER);
  BEGIN CurCol := col
  END SetColor;

  PROCEDURE SetOffset* (voff: INTEGER);
  BEGIN CurOff := voff
  END SetOffset;

  (*logs and text selections*)

  PROCEDURE OpenLog* (T: Texts.Text);
  BEGIN Log := T
  END OpenLog;

  PROCEDURE GetSelection* (VAR text: Texts.Text; VAR beg, end, time: LONGINT); (*from current display*)
    VAR M: SelectionMsg;
  BEGIN M.time := -1; Viewers.Broadcast(M); time := M.time;
    IF time >= 0 THEN text := M.text; beg := M.beg; end := M.end END
  END GetSelection;

  (*display management*)

  PROCEDURE HandleFiller (V: Viewers.Frame; VAR M: Viewers.FrameMsg);
  BEGIN
    CASE M OF
    Viewers.InputMsg: IF M.id = Viewers.track THEN DrawMouseArrow(M.X, M.Y) END |
    Viewers.ControlMsg: IF M.id = Viewers.mark THEN DrawPointerStar(M.X, M.Y) END |
    Viewers.ViewerMsg:
      IF (M.id = Viewers.restore) & (V.W > 0) & (V.H > 0) THEN
        RemoveMarks(V.X, V.Y, V.W, V.H);
        Display.ReplConst(Display.black, V.X, V.Y, V.W, V.H, Display.replace)
      ELSIF M.id = Viewers.modify THEN
        IF M.Y < V.Y THEN
          RemoveMarks(V.X, M.Y, V.W, V.Y - M.Y);
          Display.ReplConst(Display.black, V.X, M.Y, V.W, V.Y - M.Y, Display.replace)
        ELSIF M.Y > V.Y THEN RemoveMarks(V.X, V.Y, V.W, M.Y - V.Y)
        END
      END
    END
  END HandleFiller;

  PROCEDURE InitTrack* (D: Viewers.Display; W, H: INTEGER); (*add new track to the right*)
    VAR Filler: Viewers.Viewer;
  BEGIN NEW(Filler); Filler.handle := HandleFiller; Viewers.InitTrack(D, W, H, Filler)
  END InitTrack;

  PROCEDURE OpenTrack* (D: Viewers.Display; X, W: INTEGER); (*create overlay track at X*)
    VAR Filler: Viewers.Viewer;
  BEGIN NEW(Filler); Filler.handle := HandleFiller; Viewers.OpenTrack(D, X, W, Filler)
  END OpenTrack;

  PROCEDURE InitDisplay* (D: Viewers.Display; name: ARRAY OF CHAR);
  BEGIN Viewers.InitDisplay(D, DW, DH, name);
    InitTrack(D, DW DIV 8 * 5, DH);
    InitTrack(D, DW DIV 8 * 3, DH)
  END InitDisplay;

  PROCEDURE SetDisplay* (D: Viewers.Display);
  BEGIN Viewers.SetDisplay(D); Input.SetMouseLimits(D.curW, D.H)
  END SetDisplay;

  PROCEDURE CloseDisplay* (D: Viewers.Display; hint: INTEGER);
    VAR prev: Viewers.Display;
  BEGIN prev := Viewers.CurDisplay; Viewers.CloseDisplay(D, hint);
    IF Viewers.CurDisplay # prev THEN Input.SetMouseLimits(Viewers.CurDisplay.curW, Viewers.CurDisplay.H) END
  END CloseDisplay;

  PROCEDURE DisplayWidth* (X: INTEGER): INTEGER;
  BEGIN RETURN DW
  END DisplayWidth;

  PROCEDURE DisplayHeight* (X: INTEGER): INTEGER;
  BEGIN RETURN DH
  END DisplayHeight;

  PROCEDURE MarkedViewer* (): Viewers.Viewer;
  BEGIN RETURN Viewers.This(Viewers.CurDisplay, Pointer.X, Pointer.Y)
  END MarkedViewer;

  PROCEDURE ThisViewer* (): Viewers.Viewer; (*for use in viewer close commands*)
    VAR V: Viewers.Viewer;
  BEGIN IF Par.frame = Par.vwr.dsc THEN V := Par.vwr ELSE V := MarkedViewer() END ;
    RETURN V
  END ThisViewer;

  (*standard Oberon display with user track and system track, and filler viewer*)

  PROCEDURE UserTrack* (X: INTEGER): INTEGER;
  BEGIN RETURN X DIV DW * DW
  END UserTrack;

  PROCEDURE SystemTrack* (X: INTEGER): INTEGER;
  BEGIN RETURN X DIV DW * DW + DW DIV 8 * 5
  END SystemTrack;

  PROCEDURE UY (X: INTEGER): INTEGER;
    VAR y: INTEGER;
      fil, bot, alt, max: Viewers.Frame;
  BEGIN Viewers.Locate(Viewers.CurDisplay, X, 0, fil, bot, alt, max);
    IF fil.H >= DH DIV 8 THEN y := DH ELSE y := max.Y + max.H DIV 2 END ;
    RETURN y
  END UY;

  PROCEDURE AllocateUserViewer* (DX: INTEGER; VAR X, Y: INTEGER);
  BEGIN
    IF PointerOn() THEN X := Pointer.X; Y := Pointer.Y
    ELSE X := DX DIV DW * DW; Y := UY(X)
    END
  END AllocateUserViewer;

  PROCEDURE SY (X: INTEGER): INTEGER;
    VAR H0, H1, H2, H3, y: INTEGER;
      fil, bot, alt, max: Viewers.Frame;
  BEGIN H3 := DH - DH DIV 3; H2 := H3 - H3 DIV 2; H1 := DH DIV 5; H0 := DH DIV 10;
    Viewers.Locate(Viewers.CurDisplay, X, DH, fil, bot, alt, max);
    IF fil.H >= DH DIV 8 THEN y := DH
    ELSIF max.H >= DH - H0 THEN y := max.Y + H3
    ELSIF max.H >= H3 - H0 THEN y := max.Y + H2
    ELSIF max.H >= H2 - H0 THEN y := max.Y + H1
    ELSE y := max.Y + max.H DIV 2
    END ;
    RETURN y
  END SY;

  PROCEDURE AllocateSystemViewer* (DX: INTEGER; VAR X, Y: INTEGER);
  BEGIN
    IF PointerOn() THEN X := Pointer.X; Y := Pointer.Y
    ELSE X := DX DIV DW * DW + DW DIV 8 * 5; Y := SY(X)
    END
  END AllocateSystemViewer;

  (*command interpretation*)

  PROCEDURE SetPar*(F: Viewers.Frame; T: Texts.Text; pos: LONGINT);
  BEGIN Par.vwr := Viewers.ThisViewer(F); Par.frame := F; Par.text := T; Par.pos := pos
  END SetPar;

  PROCEDURE Call* (name: ARRAY OF CHAR; VAR Mname, Cname: ARRAY OF CHAR; VAR res: INTEGER);
    VAR mod: Modules.Module; P: Modules.Command;
      i, j: INTEGER; ch: CHAR;
  BEGIN i := 0; ch := name[0];
    IF ("0" <= ch) & (ch <= "9") THEN (*module number*) j := 0;
      REPEAT j := 10*j + (ORD(ch) - 30H); INC(i); ch := name[i] UNTIL (ch < "0") OR (ch > "9");
      IF ch = "." THEN INC(i); mod := Modules.root;
        WHILE (mod # NIL) & (mod.num # j) DO mod := mod.next END ;
        IF (mod # NIL) & (mod.name[0] # 0X) THEN res := 0; j := 0;
          REPEAT ch := mod.name[j]; Mname[j] := ch; INC(j)  UNTIL ch = 0X
        ELSE res := 8
        END
      ELSE res := 9
      END
    ELSIF (ch >= "A") & (ch <= "Z") OR (ch >= "a") & (ch <= "z") OR (ch = "*") THEN (*module name*)
      REPEAT Mname[i] := ch; INC(i); ch := name[i] UNTIL (ch = ".") OR (ch = 0X);
      IF ch = "." THEN Mname[i] := 0X; INC(i); Modules.Load(Mname, mod); res := Modules.res ELSE res := 9 END
    ELSE res := 9
    END ;
    IF res = 0 THEN
      j := 0; ch := name[i]; INC(i);
      WHILE ch # 0X DO Cname[j] := ch; INC(j); ch := name[i]; INC(i) END ;
      Cname[j] := 0X;
      P := Modules.ThisCommand(mod, Cname); res := Modules.res;
      IF Modules.res = 0 THEN P END
    END
  END Call;

  PROCEDURE Activate*(F: Viewers.Frame; T: Texts.Text; pos: LONGINT); (*command*)
    VAR S: Texts.Scanner; res: INTEGER;
      Mname, Cname: ARRAY 32 OF CHAR;
  BEGIN
    Texts.OpenScanner(S, T, pos); Texts.Scan(S);
    IF ((S.class = Texts.Name) OR (S.class = Texts.String)) & (S.line = 0) THEN (*strings allowed*)
      SetPar(F, T, pos + S.len); Call(S.s, Mname, Cname, res);
      IF (res > 0) & (Log # NIL) THEN
        Texts.WriteString(W, "Call error: ");
        IF res = 1 THEN Texts.WriteString(W, Modules.importing); Texts.WriteString(W, " module not found")
        ELSIF res = 2 THEN Texts.WriteString(W, Modules.importing); Texts.WriteString(W, " bad version")
        ELSIF res = 3 THEN Texts.WriteString(W, Modules.importing); Texts.WriteString(W, " imports ");
          Texts.WriteString(W, Modules.imported); Texts.WriteString(W, " with bad key")
        ELSIF res = 4 THEN Texts.WriteString(W, Modules.importing); Texts.WriteString(W, " corrupted obj file")
        ELSIF res = 5 THEN Texts.WriteString(W, Mname); Texts.WriteString(W, " command not found")
        ELSIF res = 7 THEN Texts.WriteString(W, Modules.importing); Texts.WriteString(W, " insufficient space")
        ELSIF res = 8 THEN Texts.WriteString(W, Mname); Texts.WriteString(W, " module not found")
        ELSIF res = 9 THEN Texts.WriteString(W, S.s); Texts.WriteString(W, " invalid command")
        END ;
        Texts.WriteLn(W); Texts.Append(Log, W.buf)
      END
    END
  END Activate;

  (*task management*)

  PROCEDURE GC;
    VAR mod: Modules.Module;
  BEGIN
    IF (ActCnt <= 0) OR (Kernel.allocated >= Kernel.heapLim - Kernel.heapOrg - 10000H) THEN
      mod := Modules.root; LED(21H);
      WHILE mod # NIL DO
        IF mod.name[0] # 0X THEN Kernel.Mark(mod.ptr) END ;
        mod := mod.next
      END ;
      LED(23H);
      Files.RestoreList; LED(27H);
      Kernel.Collect; LED(20H);
      Modules.Collect;
      ActCnt := BasicCycle
    END
  END GC;

  PROCEDURE NewTask*(h: Handler; period: INTEGER): Task;
    VAR t: Task;
  BEGIN NEW(t); t.state := off; t.next := t; t.handle := h; t.period := period; RETURN t
  END NewTask;
  
  PROCEDURE Install* (T: Task);
  BEGIN
    IF T.state = off THEN
      T.next := CurTask.next; CurTask.next := T; T.state := idle; T.nextTime := 0; INC(NofTasks)
    END
  END Install;

  PROCEDURE Remove* (T: Task);
    VAR t: Task;
  BEGIN
    IF T.state # off THEN t := T;
      WHILE t.next # T DO t := t.next END ;
      t.next := T.next; T.state := off; T.next := NIL; CurTask := t; DEC(NofTasks)
    END
  END Remove;

  PROCEDURE Collect* (count: INTEGER);
  BEGIN ActCnt := count
  END Collect;

  PROCEDURE Loop*;
    VAR V: Viewers.Viewer; M: InputMsg; N: Viewers.ControlMsg;
      prevX, prevY, X, Y, t: INTEGER; keys: SET; ch: CHAR;
  BEGIN
    REPEAT
      Input.Mouse(keys, X, Y);
      IF Input.Available() > 0 THEN Input.Read(ch);
        IF ch = ESC THEN
          N.id := Viewers.neutralize; Viewers.Broadcast(N); FadePointer; LED(0)
        ELSIF ch = SETSTAR THEN
          N.id := Viewers.mark; N.X := X; N.Y := Y; V := Viewers.This(Viewers.CurDisplay, X, Y); V.handle(V, N)
        ELSE M.id := Viewers.consume; M.ch := ch; M.fnt := CurFnt; M.col := CurCol; M.voff := CurOff;
          V := Viewers.FocusViewer; V.handle(V, M); DEC(ActCnt)
        END
      ELSIF keys # {} THEN
        M.id := Viewers.track; M.X := X; M.Y := Y; M.keys := keys;
        REPEAT V := Viewers.This(Viewers.CurDisplay, M.X, M.Y); V.handle(V, M); Input.Mouse(M.keys, M.X, M.Y)
        UNTIL M.keys = {};
        DEC(ActCnt)
      ELSE
        IF (X # prevX) OR (Y # prevY) OR ~MouseOn() THEN
          M.id := Viewers.track; M.X := X;
          IF Y >= DH THEN Y := DH END ;
          M.Y := Y; M.keys := keys; V := Viewers.This(Viewers.CurDisplay, X, Y); V.handle(V, M); prevX := X; prevY := Y
        END ;
        CurTask := CurTask.next; t := Kernel.Time();
        IF t >= CurTask.nextTime THEN
          CurTask.nextTime := t + CurTask.period; CurTask.state := active; CurTask.handle; CurTask.state := idle
        END
      END
    UNTIL FALSE
  END Loop;

  PROCEDURE Reset*;
  BEGIN
    IF CurTask.state = active THEN Remove(CurTask) END ;
    SYSTEM.LDREG(14, Kernel.stackOrg); (*reset stack pointer*) Loop
  END Reset;

BEGIN User[0] := 0X;
  Arrow.Fade := FlipArrow; Arrow.Draw := FlipArrow;
  Star.Fade := FlipStar; Star.Draw := FlipStar;
  OpenCursor(Mouse); OpenCursor(Pointer);

  DW := Display.Width; DH := Display.Height; CL := DW;
  CurFnt := Fonts.Default; CurCol := Display.white; CurOff := 0;

  ActCnt := 0; CurTask := NewTask(GC, 1000); Install(CurTask);
  Texts.OpenWriter(W); Log := NIL;

  IF Modules.importing = "Oberon" THEN (*loaded by the regular loader*)
    Modules.Load("System", Mod); Mod := NIL; Loop
  END
END Oberon.
