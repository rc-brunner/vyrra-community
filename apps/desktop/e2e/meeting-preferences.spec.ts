import {expect,test} from "@playwright/test";
const pic="iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+mAkwAAAAASUVORK5CYII=";
test.beforeEach(async({page})=>{await page.addInitScript(({pic})=>{
  const view={profile:{name:"Vyrra Notes",server:"",source:"com.apple.Safari",image:null as string|null},sources:[["com.apple.Safari","Safari"]],avatar:pic,plans:[]};
  const prefs={language:null,translateToEnglish:false, vocabulary:["Vyrra"],snippets:[],sound:"classic",panelSounds:false};
  const calls:string[]=[];Object.assign(window,{qaCalls:calls,isTauri:true,__TAURI_INTERNALS__:{invoke:async(cmd:string,args:Record<string,unknown>)=>{calls.push(cmd);switch(cmd){
    case "meeting_list":return structuredClone(view);
    case "meeting_profile":Object.assign(view.profile,args);return;
    case "meeting_picture":view.profile.image=args.reset?null:"custom";return;
    case "dictation_models":return {installed:["base"],active:"base",job:null,idle:true};
    case "dictation_options":return structuredClone(prefs);
    case "dictation_set_feedback":Object.assign(prefs,args);return;
    case "dictation_preview_sound":return;
    case "dictation_languages":return [["en","English"]];
    case "panel_sound":return;
    default:throw Error("Unexpected IPC command: "+cmd);
  }}}});},{pic});});
test("sound menu supports keyboard, preview, immediate persistence, and mute",async({page})=>{
  await page.goto("/#/settings/dictation");const trigger=page.getByRole("button",{name:/^Dictation sound,/});await trigger.focus();await page.keyboard.press("ArrowDown");const list=page.getByRole("listbox");await expect(list).toBeFocused();await page.keyboard.press("ArrowDown");await page.keyboard.press("ArrowDown");await page.keyboard.press("Enter");await expect(trigger).toHaveAccessibleName("Dictation sound, Felt thud");
  await page.getByRole("button",{name:"Preview start and finish sounds"}).click();expect(await page.evaluate(()=>Reflect.get(window,"qaCalls"))).toContain("dictation_preview_sound");
  await trigger.click();await page.keyboard.press("Escape");await expect(list).toHaveCount(0);await expect(trigger).toBeFocused();await page.getByRole("checkbox",{name:/opening and closing/}).check();
  await page.getByRole("link",{name:"Appearance"}).click();await page.getByRole("link",{name:"Dictation",exact:true}).click();await expect(trigger).toHaveAccessibleName("Dictation sound, Felt thud");await expect(page.getByRole("checkbox",{name:/opening and closing/})).toBeChecked();
  await trigger.click();await page.keyboard.press("End");await page.keyboard.press("Enter");await expect(page.getByRole("button",{name:"Preview start and finish sounds"})).toBeDisabled();expect(await page.getByRole("textbox",{name:"Personal dictionary"}).inputValue()).toBe("Vyrra");
});
test("participant picture action reveals on focus, profile persists and can reset",async({page})=>{
  await page.goto("/#/settings/meetings");const pic=page.getByRole("button",{name:"Choose participant picture"});await pic.focus();await expect(page.getByRole("tooltip")).toHaveText("Choose participant picture");await page.keyboard.press("Enter");await expect(page.getByRole("button",{name:"Restore Vyrra icon"})).toBeVisible();await page.getByRole("textbox",{name:"Participant name"}).fill("Studio Notetaker");await page.getByRole("button",{name:"Save preferences"}).click();await expect(page.getByRole("status")).toHaveText("Meeting preferences saved.");await page.getByRole("button",{name:"Restore Vyrra icon"}).click();await expect(page.getByRole("button",{name:"Restore Vyrra icon"})).toHaveCount(0);
});
