const test=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs'),os=require('node:os'),path=require('node:path');
const {Database}=require('../src/main/database');
const {Repository}=require('../src/main/repository');

async function setup(){const dir=fs.mkdtempSync(path.join(os.tmpdir(),'its-test-'));const db=new Database(path.join(dir,'test.sqlite'));await db.open();return new Repository(db)}

test('creates a long Idea with defaults and soft deletes it',async()=>{const repo=await setup();const id=repo.save('idea',{content:'第一段\n\n第二段',status:'New'});const idea=repo.list('idea')[0];assert.equal(idea.id,id);assert.equal(idea.content,'第一段\n\n第二段');assert.equal(idea.status,'New');assert.ok(idea.created_at);assert.ok(idea.updated_at);repo.remove('idea',id);assert.equal(repo.list('idea').length,0)});

test('supports tasks with or without deadline and records completion',async()=>{const repo=await setup();repo.save('task',{title:'无截止任务',status:'Todo'});const id=repo.save('task',{title:'有截止任务',deadline:'2026-09-25',status:'Todo'});let task=repo.list('task').find(x=>x.id===id);assert.equal(task.deadline,'2026-09-25');repo.save('task',{...task,status:'Done',topic_ids:[]});task=repo.list('task').find(x=>x.id===id);assert.ok(task.completed_at);assert.equal(repo.list('task').find(x=>x.title==='无截止任务').deadline,null)});

test('aggregates Idea, Task and Schedule by Topic',async()=>{const repo=await setup();const topicId=repo.saveTopic({name:'Program Analysis',description:'程序分析'});repo.save('idea',{content:'做可视化工具',status:'New',topic_ids:[topicId]});repo.save('task',{title:'阅读 LLVM 文档',status:'Doing',topic_ids:[topicId]});repo.save('schedule',{title:'程序分析组会',date:'2026-09-25',start_time:'14:00',end_time:'16:00',topic_ids:[topicId]});const detail=repo.topicDetail(topicId);assert.equal(detail.ideas.length,1);assert.equal(detail.tasks.length,1);assert.equal(detail.schedules.length,1)});

test('rejects invalid schedule time range',async()=>{const repo=await setup();assert.throws(()=>repo.save('schedule',{title:'错误日程',date:'2026-09-25',start_time:'16:00',end_time:'14:00'}),/结束时间/)});
